# StockOps AWS 리소스 인벤토리 (서울 리전)

> 현재까지 구축된 AWS 리소스 전체 목록. 리전: `ap-northeast-2` (서울)
> 계정: `448768137813`
> IaC: Terraform (`Stockops-Infra/modules` + `seoul`)
> Terraform State: S3 (`siseon-terraform-state/infra/terraform.tfstate`)

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
| `stockops-eso-role` | ESO (IRSA) | Secrets Manager GetSecretValue, DescribeSecret |
| `github-actions-ecr-push` | GitHub Actions OIDC | ECR Push, EKS DescribeCluster |

### IRSA / OIDC
- OIDC Provider (EKS 클러스터 연동)
- AWS Load Balancer Controller: `kube-system/aws-load-balancer-controller` SA
- ESO: `external-secrets/external-secrets` SA
- GitHub Actions: OIDC Provider (`token.actions.githubusercontent.com`)

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
- 엔드포인트: `module.seoul_db.db_address:5432` (Terraform 참조)

### 서브넷 그룹
- 이름: `seoul-db-subnet-group`
- Private DB 서브넷 (Multi-AZ 대비)

> 스키마는 Flyway로 관리. 앱 기동 시 자동 적용.

---

## 5. ECR (modules/ecr — for_each)

4개 리포지토리 (이미지 태그: `latest`)

| 리포지토리 | 이미지 |
|-----------|--------|
| `stockops-api` | Spring Boot 백엔드 |
| `stockops-ai` | FastAPI AI 모듈 |
| `stockops-admin-web` | 관리자 React + nginx |
| `stockops-client-web` | 사용자 React + nginx |

레지스트리: `448768137813.dkr.ecr.ap-northeast-2.amazonaws.com`

---

## 6. GitHub Actions OIDC (modules/github-oidc)

- OIDC Provider: `token.actions.githubusercontent.com`
- IAM Role: `github-actions-ecr-push`
- 허용 브랜치: `main` (`repo:jinuuuKim/Stockops-Application:ref:refs/heads/main`)
- 권한: ECR Push (4개 리포), EKS DescribeCluster

---

## 7. IoT Core (modules/iot)

| 리소스 | 상세 |
|--------|------|
| IoT Thing | `stockops-sensor` |
| 인증서 | X.509 (Terraform 관리, sensitive output) |
| IoT 정책 | connect/publish/subscribe/receive 허용 |
| IoT Rule | Topic: `sensimul/sites/+/sensors/+` → SQS 전달 |
| SQS 큐 | `stockops-sensor-data` |
| DLQ | `stockops-sensor-data-dlq` |
| IoT 엔드포인트 | `a2ie1b3xp2emgi-ats.iot.ap-northeast-2.amazonaws.com` |

> ⚠️ destroy 후 재apply 시 인증서가 새로 발급됨. 온프레미스 브리지 설정에 사용한 인증서 무효화 → 재추출 후 재전달 필요.

---

## 8. Secrets Manager

| 리소스 | 상세 |
|--------|------|
| 시크릿 이름 | `stockops/app` |
| 저장 키 | `JWT_SECRET`, `DB_USERNAME`, `DB_PASSWORD` |
| 복구 기간 | 0일 (즉시 삭제, dev 환경) |
| 접근 권한 | `stockops-eso-role` (IRSA) |

> 실제 값은 `terraform.tfvars`에서 관리. Git 비추적 (`.gitignore`).

---

## 9. S3

| 버킷 | 용도 |
|------|------|
| `siseon-terraform-state` | Terraform state backend (`infra/terraform.tfstate`) |

- 버저닝: 활성화 (state 롤백 가능)

---

## 10. Kubernetes 리소스 (seoul/kubernetes.tf)

### 네임스페이스
- `stockops` (앱)
- `external-secrets` (ESO)
- `kube-system` (LBC)

### Helm Release
- `external-secrets` (External Secrets Operator)
- `aws-load-balancer-controller` (kube-system)

### Deployment / Service (네임스페이스: stockops)

| Deployment | Service | 포트 | 비고 |
|-----------|---------|------|------|
| stockops-client-web | stockops-client-web-svc | 80 | wait_for_rollout=false |
| stockops-admin-web | stockops-admin-web-svc | 80 | wait_for_rollout=false |
| stockops-api | stockops-api-svc | 8080 | wait_for_rollout=false |
| stockops-ai | stockops-ai-svc | 8000 | wait_for_rollout=false |
| stockops-redis | stockops-redis-svc | 6379 | redis:7-alpine |

### TargetGroupBinding (kubectl_manifest)
- stockops-client-tgb → seoul-frontend-tg
- stockops-admin-tgb → seoul-admin-tg
- stockops-api-tgb → seoul-spring-tg
- stockops-ai-tgb → seoul-fastapi-tg
- 모두 `targetType: ip`, `depends_on = LBC`

### ESO 리소스 (kubectl_manifest)
- `ClusterSecretStore`: `stockops-secret-store` (AWS Secrets Manager 연결)
- `ExternalSecret`: `stockops-external-secret` (1h 주기, `stockops-secret` 자동 생성)

### Secret
- `stockops-secret`: ESO가 자동 생성/관리 (JWT_SECRET, DB_USERNAME, DB_PASSWORD)
- destroy/재apply 후 ESO가 자동 복구 — 수동 생성 불필요

### api-server 주요 환경변수
- `SPRING_PROFILES_ACTIVE=dev`
- `STOCKOPS_DATASOURCE_URL` = `jdbc:postgresql://${module.seoul_db.db_address}:5432/stockops`
- `STOCKOPS_DATASOURCE_USERNAME/PASSWORD` (stockops-secret 참조)
- `SPRING_DATA_REDIS_HOST=stockops-redis-svc`
- `JWT_SECRET` (stockops-secret 참조)
- `SPRING_MAIL_*` (현재 더미값)
- `MANAGEMENT_ENDPOINT_HEALTH_SHOW_DETAILS=always`

---

## 11. 과금 주의 리소스 (destroy 시 꼭 확인)

| 리소스 | 과금 방식 |
|--------|-----------|
| NAT Gateway | 시간당 + 데이터 처리량 |
| RDS 인스턴스 | 시간당 (실행 중일 때) |
| ALB | 시간당 + LCU |
| EKS 클러스터 | 시간당 ($0.10/hr) |
| EC2 노드 (t3.medium × 2) | 시간당 |
| EBS (노드 볼륨) | GB-월 |

destroy 후 잔재 확인:

```powershell
aws ec2 describe-nat-gateways --filter "Name=state,Values=available" --query "NatGateways[*].NatGatewayId" --output table
aws rds describe-db-instances --query "DBInstances[*].DBInstanceIdentifier" --output table
aws elbv2 describe-load-balancers --query "LoadBalancers[*].LoadBalancerName" --output table
aws iam list-roles --query "Roles[?contains(RoleName, 'seoul') || contains(RoleName, 'stockops') || contains(RoleName, 'github-actions')].RoleName" --output table
```

---

## 12. Terraform 모듈 의존 관계

```
seoul/main.tf
├── module.seoul_vpc          (VPC, 서브넷, IGW, NAT)
├── module.seoul_alb          (ALB, 리스너, 4개 TG)         ← vpc
├── module.seoul_eks          (EKS, 노드그룹, IAM, IRSA)    ← vpc, sg
├── module.seoul_db           (RDS, 서브넷그룹)              ← vpc, sg
└── module.seoul_ecr          (4개 ECR, for_each)

seoul/iam.tf
├── module.github_oidc        (OIDC Provider + IAM Role)    ← ecr
└── aws_iam_role.eso          (ESO IRSA)                    ← eks.oidc

seoul/iot.tf
└── module.seoul_iot          (IoT Thing, 인증서, SQS)

seoul/secrets.tf
└── aws_secretsmanager_secret (stockops/app)

seoul/kubernetes.tf
├── helm_release.external_secrets
├── helm_release.aws_load_balancer_controller               ← eks
├── deployment/service × 5
├── kubectl_manifest (TGB × 4)                             ← LBC, alb TG
├── kubectl_manifest.secret_store (ClusterSecretStore)     ← ESO
└── kubectl_manifest.external_secret (ExternalSecret)      ← secret_store
```

---

## 13. 아직 미구축 (로드맵)

| 항목 | 우선순위 |
|------|----------|
| Route 53 + ACM (도메인 연결, 호스트 분리) | 높음 |
| ArgoCD (GitOps CD) | 높음 |
| IoT 브리지 연결 확인 | 중간 |
| Global Accelerator | 낮음 |
| 오하이오 리전 전체 스택 | 낮음 |
| Azure 서울 백업/로그 | 낮음 |
| Observability 스택 | 낮음 |

---

*최종 업데이트: 2026-06-08 / GitHub Actions OIDC, IoT 파이프라인, S3 backend, Secrets Manager + ESO 연동, 계정 448768137813 반영*
