# StockOps AWS 리소스 인벤토리 (서울 리전)

> 현재까지 구축된 AWS 리소스 전체 목록. 리전: `ap-northeast-2` (서울)
> 계정: `247385839803`
> IaC: Terraform (`Stockops-Infra/modules` + `seoul`)

---

## 1. 네트워크 (modules/vpc)

### VPC
- CIDR: `10.0.0.0/16`
- 이름: `seoul-vpc`

### 서브넷 (3-Tier, 2 AZ: ap-northeast-2a / 2c)

| 계층 | AZ-a | AZ-c | 용도 |
|------|------|------|------|
| Public | `10.0.1.0/24` | `10.0.2.0/24` | ALB, NAT Gateway |
| Private App | `10.0.11.0/24` | `10.0.12.0/24` | EKS 워커 노드, Pod |
| Private DB | `10.0.21.0/24` | `10.0.22.0/24` | RDS |

### 기타 네트워크
- Internet Gateway (public 서브넷용)
- NAT Gateway (private 서브넷 아웃바운드용) — **시간당 과금 주의**
- 라우팅 테이블 (public/private)

---

## 2. 로드밸런서 (modules/alb)

### ALB
- 이름: `seoul-alb`
- 리스너: HTTP :80
- 타입: Application Load Balancer (public 서브넷)

### 리스너 규칙 (우선순위 순)

| 우선순위 | 경로 조건 | 대상 그룹 |
|----------|-----------|-----------|
| 85 | `/admin`, `/admin/*` | seoul-admin-tg |
| 90 | `/api`, `/api/*` | seoul-spring-tg |
| 100 | `/ai`, `/ai/*` | seoul-fastapi-tg |
| default | (그 외 전부) | seoul-frontend-tg |

### 대상 그룹 (Target Group)

| 이름 | 포트 | 헬스체크 경로 | 연결 서비스 |
|------|------|---------------|-------------|
| seoul-frontend-tg | 80 | `/` | client-web |
| seoul-admin-tg | 80 | `/` | admin-web |
| seoul-spring-tg | 8080 | `/actuator/health` | api-server |
| seoul-fastapi-tg | 8000 | `/health` | ai-module |

> 대상 등록은 K8s의 TargetGroupBinding + AWS Load Balancer Controller가 Pod IP를 자동 등록 (targetType: ip).

---

## 3. EKS (modules/eks)

### 클러스터
- 이름: `seoul-cluster`
- 버전: `1.30`
- 엔드포인트: private + public access
- 서브넷: Private App 서브넷

### 노드 그룹
- 이름: `seoul-managed-node-group`
- 인스턴스: `t3.medium`
- 스케일링: desired 2 / min 2 / max 4

### IAM Role (EKS 관련)

| Role | 용도 | 연결 정책 |
|------|------|-----------|
| `seoul-eks-cluster-role` | EKS 컨트롤플레인 | AmazonEKSClusterPolicy |
| `seoul-eks-node-role` | 워커 노드 | WorkerNodePolicy, CNI_Policy, ECR ReadOnly |
| `seoul-lbc-role` | AWS LB Controller (IRSA) | 커스텀 `seoul-lbc-policy` |

### IRSA / OIDC
- OIDC Provider (EKS 클러스터 연동)
- AWS Load Balancer Controller가 `kube-system` 네임스페이스의 `aws-load-balancer-controller` ServiceAccount로 IAM Role 사용

### 보안 그룹 규칙
- `seoul-app-sg` → EKS 클러스터 SG 인바운드 전체 허용
- EKS 클러스터 SG → RDS SG 5432 인바운드 허용

---

## 4. RDS (modules/db)

### DB 인스턴스
- 식별자: `seoul-rds-postgres`
- 엔진: PostgreSQL 16
- 인스턴스 클래스: `db.t4g.micro` (Graviton)
- 스토리지: gp3 20GB (최대 100GB 자동확장)
- DB명: `stockops`
- 퍼블릭 액세스: 비활성
- 백업 보존: 7일
- 엔드포인트: `seoul-rds-postgres.<...>.ap-northeast-2.rds.amazonaws.com:5432`

### 서브넷 그룹
- 이름: `seoul-db-subnet-group`
- Private DB 서브넷 (Multi-AZ 대비)

> 스키마는 Flyway로 관리 (38개 마이그레이션). 앱 기동 시 자동 적용.

---

## 5. ECR (modules/ecr — for_each)

4개 리포지토리 (이미지 태그: `latest`)

| 리포지토리 | 이미지 |
|-----------|--------|
| `stockops-api` | Spring Boot 백엔드 |
| `stockops-ai` | FastAPI AI 모듈 |
| `stockops-admin-web` | 관리자 React + nginx |
| `stockops-client-web` | 사용자 React + nginx |

레지스트리: `247385839803.dkr.ecr.ap-northeast-2.amazonaws.com`

---

## 6. Kubernetes 리소스 (seoul/kubernetes.tf)

### 네임스페이스
- `stockops` (앱)
- `external-secrets` (ESO)
- `kube-system` (LBC)

### Helm Release
- `external-secrets` (External Secrets Operator) — 추후 Secrets Manager 연동용
- `aws-load-balancer-controller` (kube-system)

### Deployment / Service (네임스페이스: stockops)

| Deployment | Service | 포트 | 비고 |
|-----------|---------|------|------|
| stockops-client-web | stockops-client-web-svc | 80 | wait_for_rollout=false |
| stockops-admin-web | stockops-admin-web-svc | 80 | wait_for_rollout=false |
| stockops-api | stockops-api-svc | 8080 | wait_for_rollout=false |
| stockops-ai | stockops-ai-svc | 8000 | wait_for_rollout=false |
| stockops-redis | stockops-redis-svc | 6379 | redis:7-alpine |

모든 Service는 ClusterIP. 외부 노출은 ALB + TargetGroupBinding 경유.

### TargetGroupBinding (kubectl_manifest)
- stockops-client-tgb → seoul-frontend-tg
- stockops-admin-tgb → seoul-admin-tg
- stockops-api-tgb → seoul-spring-tg
- stockops-ai-tgb → seoul-fastapi-tg
- 모두 `targetType: ip`, `depends_on = LBC`

### Secret (kubectl 수동 생성, Terraform 관리 아님)
- `stockops-secret`: JWT_SECRET, DB_USERNAME, DB_PASSWORD
- ⚠️ 클러스터 삭제 시 함께 사라짐. 재구축 시 재생성 필요.
- 추후 Secrets Manager + ESO로 대체 예정.

### api-server 주요 환경변수
- `SPRING_PROFILES_ACTIVE=dev`
- `STOCKOPS_DATASOURCE_URL/USERNAME/PASSWORD` (RDS)
- `SPRING_DATA_REDIS_HOST=stockops-redis-svc`
- `JWT_SECRET` (Secret)
- `SPRING_MAIL_*` (현재 더미값)
- `MANAGEMENT_ENDPOINT_HEALTH_SHOW_DETAILS=always`

---

## 7. 과금 주의 리소스 (destroy 시 꼭 확인)

| 리소스 | 과금 방식 |
|--------|-----------|
| NAT Gateway | 시간당 + 데이터 처리량 |
| RDS 인스턴스 | 시간당 (실행 중일 때) |
| ALB | 시간당 + LCU |
| EKS 클러스터 | 시간당 ($0.10/hr) |
| EC2 노드 (t3.medium × 2) | 시간당 |
| EBS (노드 볼륨) | GB-월 |

destroy 후 `describe-nat-gateways`, `describe-db-instances`, `describe-load-balancers`로 잔재 확인 필수.

---

## 8. Terraform 모듈 의존 관계

```
seoul/main.tf
├── module.seoul_vpc      (VPC, 서브넷, IGW, NAT)
├── module.seoul_alb      (ALB, 리스너, 4개 TG)        ← vpc
├── module.seoul_eks      (EKS, 노드그룹, IAM, IRSA)    ← vpc, sg
├── module.seoul_db       (RDS, 서브넷그룹)             ← vpc, sg
└── module.seoul_ecr      (4개 ECR, for_each)

seoul/kubernetes.tf
├── helm_release.external_secrets
├── helm_release.aws_load_balancer_controller  ← eks
├── deployment/service × 5
└── kubectl_manifest (TGB × 4)                  ← LBC, alb TG
```

---

## 9. 아직 미구축 (로드맵)

- Route 53 (DNS, 페일오버)
- ACM (TLS 인증서)
- Global Accelerator (리전 간 라우팅)
- Secrets Manager (시크릿 중앙화)
- Site-to-Site VPN (온프레미스 연결)
- IoT Core (센서 데이터 수신)
- SQS (센서 데이터 큐)
- S3 (데이터/로그 저장)
- 오하이오 리전 전체 스택 (멀티 리전)
- Azure 서울 백업/로그 (하이브리드)

---

*문서 작성일: 2026-06-05*