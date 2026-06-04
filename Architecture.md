# StockOps — 멀티 하이브리드 클라우드 인프라 아키텍처

> **팀명**: 시선 (SysSun — System Surveillance & Unified Network)
> **프로젝트 주제**: AX 환경을 위한 ERP 솔루션 기반 멀티 하이브리드 클라우드 인프라 자동화 및 Observability 체계 구축
> **애플리케이션**: StockOps

---

## 1. 프로젝트 개요

StockOps는 AX(AI Transformation) 환경의 ERP 솔루션으로, 멀티 리전·하이브리드 클라우드 위에서 동작한다. 인프라 자동화(IaC)와 Observability 체계 구축을 핵심 목표로 한다.

비즈니스 맥락은 K-Food(예: 비비고 만두)의 해외 수요 증가다. 서울 본사가 운영을 총괄하고, 미국 영업팀이 현지 영업을 지원한다. 영업팀은 본사 운영에 지장을 주지 않도록 최소 권한으로 애플리케이션과 DB에 접근한다.

---

## 2. 인프라 분포

| 위치 | 역할 |
|------|------|
| AWS 서울 리전 | 본사. 한국 사용자 대상 메인 서비스 |
| AWS 오하이오 리전 | 미국 영업팀 대상 서비스 (멀티 리전 확장) |
| 온프레미스 (한국) | 센터 및 창고. 온도 센서 데이터 수집 |
| Azure 서울 | 백업 데이터 및 상시 로그 저장 (재해 복구용) |

---

## 3. 데이터 전략

- **AWS RDS Multi-AZ**로 가용성 확보
- **서울 RDS(Master) ↔ 오하이오 RDS(Slave)** 동기화
  - 미국 영업팀은 DB **읽기 전용** 접근
- **Azure 서울**에 백업 데이터 + 상시 로그 저장
  - AWS 전체 재해 발생 시 Azure에서 데이터 복구

---

## 4. 트래픽 / 라우팅 전략

- **Global Accelerator** 기반 지연(latency) 라우팅
  - 한국 사용자 → 서울 리전 접속
  - 미국 사용자 → 오하이오 리전 접속
- 한 리전 장애 시 다른 리전으로 웹 트래픽 페일오버
- 애플리케이션은 서울·미국 양 리전에서 동일하게 동작

---

## 5. 온프레미스 연동 (센서 데이터 파이프라인)

서울 센터 및 온프레미스 창고에서 **온도 값 데이터**를 수집하여 AWS로 전송한다. 전송된 데이터는 백엔드로 전달되어 데이터 분석 처리에 사용된다.

```
[온프레미스 창고 센서]
        │ (온도 데이터)
        ▼
   [AWS IoT Core]  ← Site-to-Site VPN / 수신 엔드포인트
        │
        ▼
   [SQS / 백엔드]
        │
        ▼
   [데이터 분석 처리 — AI 모듈]
```

---

## 6. 애플리케이션 구성 (Stockops-Application — 모노레포)
https://github.com/jinuuuKim/Stockops-Application

| 컴포넌트 | 설명 | 포트 |
|----------|------|------|
| `stockops-client-web` | 사용자 포털 (React + nginx) | 80 |
| `stockops-admin-web` | 관리자 웹 (React + nginx) | 80 |
| `stockops-api-server` | 메인 백엔드 (Spring Boot 3.2.12, Java 21) | 8080 |
| `stockops-ai-module` | AI 수요 예측 서비스 (FastAPI) | 8000 |

- CI/CD: GitHub Actions (`.github/workflows/deploy.yml`)
  - `main` 브랜치 push 트리거 (+ `workflow_dispatch` 수동 실행 권장)
  - Build → ECR Push → EKS Rollout Restart
  - **인프라(Terraform)와는 별개 트랙.** Terraform이 ECR 리포(그릇)를 만들고, GitHub Actions가 이미지(내용물)를 채운다. `depends_on`으로 묶을 수 없음.

### 주요 애플리케이션 설정 노트
- Spring 프로파일: `local`(H2 인메모리), `dev`(PostgreSQL), `prod`(PostgreSQL). 현재 운영은 `dev` + RDS.
- 필수 환경변수: `JWT_SECRET`, `STOCKOPS_DATASOURCE_URL/USERNAME/PASSWORD`, `SPRING_DATA_REDIS_HOST`, `SPRING_MAIL_*`(현재 더미값)
- Spring 헬스체크: `/actuator/health` (Redis 연결 안 되면 전체 DOWN → Redis Pod 필수)
- FastAPI 헬스체크: `/health` (실제 엔드포인트: `/predict`, `/predict/bulk`, `/evaluate/{id}` 등, `X-API-Key` 인증)
- 모든 API 경로 prefix: `/api/v1/...`
- 초기 admin 계정: 앱 기동 시 `AuthDataLoader`가 시드 → `admin@stockops.com` / `admin123`
- 업무 데이터(상품/재고/센터/창고)는 시드 없음 → 화면/API로 직접 등록

---

## 7. 인프라 구성 (Stockops-Infra — Terraform)

### 디렉토리 구조
```
Stockops-Infra/
├── modules/
│   ├── alb/        # Application Load Balancer + Target Groups
│   ├── db/         # RDS PostgreSQL (Multi-AZ)
│   ├── ecr/        # ECR 리포지토리 (4개, for_each)
│   ├── eks/        # EKS + 노드그룹 + IRSA(LBC) + lbc-iam-policy.json
│   └── vpc/        # VPC + 3-Tier Subnets
├── seoul/          # 서울 리전 배포 (서울 단독 동작 검증 완료)
│   ├── kubernetes.tf   # NS, ESO, LBC, deploy×5, svc×5, TGB×4(kubectl_manifest)
│   ├── main.tf
│   ├── provider.tf     # aws, kubernetes(2.38), helm, kubectl(gavinbunney)
│   ├── security_groups.tf
│   └── outputs.tf
└── (ohio/)         # 오하이오 리전 — 추후 확장 예정
```

### 네트워크
- 서울 VPC CIDR: `10.0.0.0/16`
  - Public: `10.0.1.0/24`, `10.0.2.0/24`
  - Private App: `10.0.11.0/24`, `10.0.12.0/24`
  - Private DB: `10.0.21.0/24`, `10.0.22.0/24`
- 오하이오 확장 시 CIDR 충돌 방지 필요 (예: `10.1.0.0/16`)

### EKS
- 클러스터: `seoul-cluster` (버전 1.30)
- 관리형 노드그룹: t3.medium × 2 (min 2 / max 4)
- AWS Load Balancer Controller 설치 (IRSA + OIDC Provider) — helm_release
- TargetGroupBinding으로 ALB ↔ Pod 연결 (`targetType: ip` 필수)
  - `kubectl_manifest`(gavinbunney/kubectl provider)로 정의 → plan-time 검증 회피, `depends_on=LBC`로 순서 보장
- Deployment는 `wait_for_rollout = false` → 이미지 없어도 apply가 멈추지 않음
- Redis도 클러스터 내 Pod로 배포 (redis:7-alpine, ClusterIP)

### ALB 리스너 라우팅 (현행: 경로 기반)
| 경로 | 대상 |
|------|------|
| `/` (default) | client-web (frontend-tg) |
| `/admin`, `/admin/*` | admin-web (admin-tg) |
| `/api`, `/api/*` | Spring API (spring-tg) |
| `/ai`, `/ai/*` | FastAPI (fastapi-tg) |

> ⚠️ **경로 기반 라우팅의 한계**: admin을 `/admin` 서브패스로 배포하면 React `basename`, vite `base`, 쿠키 `path` 등을 모두 맞춰야 하고, 특히 refresh 토큰 쿠키 경로 문제로 새로고침 시 로그아웃되는 이슈가 있다. **→ Route 53 + ACM 단계에서 호스트 기반(`admin.도메인` / `client.도메인`)으로 전환 예정.** 호스트 분리 시 각 앱이 루트(`/`)에서 동작하여 서브패스 관련 문제가 모두 사라진다.

---

## 8. 추가 예정 서비스

| 서비스 | 용도 |
|--------|------|
| **Site-to-Site VPN** | 온프레미스 ↔ AWS 연결 |
| **IoT Core** | 온프레미스 센서 데이터 수신 |
| **SQS** | 센서 데이터 비동기 큐잉 |
| **S3** | 데이터/로그 저장 |
| **Global Accelerator** | 리전 간 지연 기반 트래픽 라우팅 |
| **Secrets Manager** | 시크릿 중앙 관리 (현재 ESO 설치됨, 마이그레이션 예정) |
| **AWS Certificate Manager (ACM)** | TLS 인증서 |
| **Route 53** | DNS + 페일오버 라우팅 + **admin/client 호스트 분리** |
| **호스트 분리 (우선순위 ↑)** | ALB를 경로 기반 → 호스트 기반으로 전환. `admin.도메인` / `client.도메인`. admin 서브패스 쿠키 문제 근본 해결 |

---

## 9. 배포 시 주의사항 (실전 메모)

### 배포 순서
- `kubectl_manifest`(TGB)는 `depends_on=LBC`로 순서가 보장되고, deployment는 `wait_for_rollout=false`라 **이미지 없이도 apply가 한 번에 끝난다.**
- 단, **EKS 클러스터가 아예 없는 최초 구축**에서는 provider가 plan 시점에 클러스터에 연결하려다 실패할 수 있어, 그 경우만 단계 분리 필요:
  ```powershell
  # 최초 1회: 인프라 먼저
  terraform apply --% -auto-approve -target=module.seoul_vpc -target=module.seoul_alb -target=module.seoul_eks -target=module.seoul_db -target=module.seoul_ecr
  aws eks update-kubeconfig --region ap-northeast-2 --name seoul-cluster
  terraform apply -auto-approve
  ```
- 클러스터가 이미 있으면 `terraform apply -auto-approve` 한 방.
- 이미지는 별도로 GitHub Actions로 채운다 (ECR 생성 후 언제든).

### 함정 모음
- nginx 프론트엔드 upstream은 K8s Service 이름(`stockops-api-svc:8080`) 사용. nginx conf는 앱 이미지에 포함되므로 수정 시 재빌드 필요.
- React 서브패스(`/admin`) 배포 시 vite `base: '/admin/'` + React Router `basename="/admin"` + nginx `alias` 모두 필요. (호스트 분리하면 불필요)
- TargetGroupBinding의 `targetType`은 immutable — 변경 시 삭제 후 재생성.
- ALB 헬스체크 경로: Spring은 `/actuator/health`(인증 불필요 경로), FastAPI는 `/health`. `/api`는 Security가 막아서 401.
- `kubernetes` provider는 2.38 고정 권장 (deployment identity 버그 회피).
- PowerShell 멀티 인자 전달 시 `--%` 연산자 사용.

### destroy
```powershell
# TGB 먼저 (LBC 살아있을 때) → 전체
terraform destroy --% -auto-approve -target=kubectl_manifest.client_tgb -target=kubectl_manifest.admin_tgb -target=kubectl_manifest.api_tgb -target=kubectl_manifest.ai_tgb
terraform destroy -auto-approve
```
- destroy 후 IAM Role(`seoul-eks-cluster-role`, `seoul-eks-node-role`, `seoul-lbc-role`)과 NAT GW/RDS/ALB 잔재 확인 필수.
- kubectl로 만든 `stockops-secret`은 클러스터와 함께 삭제됨 → 재구축 시 재생성.

---

*문서 작성일: 2026-06-05 / 서울 단독 배포 검증 완료, 방법 A(kubectl_manifest) + wait_for_rollout 적용, admin 호스트 분리 방향 결정 반영*