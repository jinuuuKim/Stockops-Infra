# 🛒 StockOps - 식품 ERP 멀티 클라우드 인프라

![Terraform](https://img.shields.io/badge/terraform-%235843U9.svg?style=for-the-badge&logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-%23316192.svg?style=for-the-badge&logo=postgresql&logoColor=white)
![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/github%20actions-%232088FF.svg?style=for-the-badge&logo=githubactions&logoColor=white)

# StockOps — 멀티 하이브리드 클라우드 인프라

> **팀명**: 시선 (SysSun — System Surveillance & Unified Network)
> **주제**: AX 환경을 위한 ERP 솔루션 기반 멀티 하이브리드 클라우드 인프라 자동화 및 Observability 체계 구축

StockOps는 K-Food 수출 기업(예: 비비고 만두)을 모델로 한 ERP/WMS 솔루션이다. 서울 본사가 운영을 총괄하고 미국 영업팀이 현지 영업을 지원하며, 멀티 리전·하이브리드 클라우드 위에서 동작한다.

---

## 시나리오

- **AWS 서울**: 본사. 한국 사용자 대상 메인 서비스
- **AWS 오하이오**: 미국 영업팀 대상 서비스 (멀티 리전 풀스택 미러)
- **온프레미스(한국)**: 센터/창고. 센서 데이터 수집
- **Azure 서울**: 백업 데이터 + 상시 로그 저장 (재해 복구용, 예정)

**데이터**: 3단계 방어 — Multi-AZ(1차) + Cross-Region Replica(2차) + Azure 백업(3차)
**트래픽**: Global Accelerator 지연 기반 라우팅 (한국→서울, 미국→오하이오), 리전 장애 시 페일오버
**보안**: 미국 영업팀은 최소 권한으로 앱/DB 접근 (본사 영향 차단)

---

## 레포 구성

| 레포 | 내용 |
|------|------|
| **Stockops-Infra** | Terraform IaC (modules + seoul + ohio + global) |
| **Stockops-Application** | 앱 모노레포 (admin-web, ai-module, api-server, client-web) + GitHub Actions |

### 애플리케이션 컴포넌트

| 컴포넌트 | 기술 | 포트 | ALB 경로 |
|----------|------|------|----------|
| client-web | React + nginx | 80 | `/` (default) |
| admin-web | React + nginx | 80 | `/admin` |
| api-server | Spring Boot 3.2.12 / Java 21 | 8080 | `/api` |
| ai-module | FastAPI | 8000 | `/ai` |

---

## 멀티 리전 구조

```
[한국 사용자]              [미국 사용자]
      │                          │
      └──────────┐   ┌───────────┘
                 ▼   ▼
          Global Accelerator
   (지연 기반 라우팅 + 장애 시 페일오버)
                 │   │
         ┌───────┘   └────────┐
         ▼                    ▼
     서울 ALB             오하이오 ALB
     (풀스택)             (풀스택 미러)
         │                    │
     서울 EKS             오하이오 EKS
  api/ai/admin/client    api/ai/admin/client
         │                    │
  서울 RDS (Master) ─────→ 오하이오 RDS (Read Replica)
  읽기/쓰기                 읽기 / 쓰기는 서울로
```

- 평상시: 한국 → 서울, 미국 → 오하이오
- 서울 장애: 한국 트래픽도 오하이오로 페일오버 + 오하이오 RDS Promote
- 오하이오 쓰기: 서울 RDS Master로 전달 (읽기는 오하이오 Replica)

---

## 인프라 디렉토리 구조

```
Stockops-Infra/
├── modules/          # 공통 모듈 (vpc, alb, eks, db, ecr, github-oidc, iot)
├── seoul/            # 서울 리전 (본사, 풀스택)
├── ohio/             # 오하이오 리전 (미국, 풀스택 미러)
└── global/           # 글로벌 리소스 (Global Accelerator)
```

### Terraform State 구조 (S3 backend)

```
siseon-terraform-state/
└── infra/
    ├── seoul/terraform.tfstate
    ├── ohio/terraform.tfstate
    └── global/terraform.tfstate
```

---

## 배포된 AWS 리소스

| 리소스 | 서울 | 오하이오 |
|--------|------|----------|
| VPC | 10.0.0.0/16 | 10.1.0.0/16 |
| EKS | seoul-cluster v1.30 | ohio-cluster v1.30 |
| ALB | 경로 기반 라우팅 | 경로 기반 라우팅 |
| RDS | PostgreSQL 16 (Master) | Read Replica |
| ECR | 4개 리포 (원본) | replication 자동 복제 |
| IoT Core + SQS | ✅ | — (서울만) |
| Secrets Manager | ✅ | ✅ (예정) |

**글로벌**: Global Accelerator (서울 + 오하이오 ALB 엔드포인트)

---

## CI/CD

```
GitHub Actions (CI)
    └─ main push / workflow_dispatch
         └─ 이미지 빌드 → 서울 ECR push (OIDC 인증, 액세스 키 없음)
              └─ 서울 ECR → 오하이오 ECR 자동 replication
                   └─ kubectl rollout restart (EKS 재배포)

ArgoCD (CD) — 설치 완료, 앱 구성 예정
    └─ GitOps 방식 배포
```

> GitHub Actions Role은 EKS `aws-auth` ConfigMap에 등록되어 있어야 `kubectl rollout restart`가 동작한다 (Terraform 관리).

---

## 시크릿 관리 (ESO)

```
Secrets Manager (stockops/app)
    └─ ClusterSecretStore
         └─ ExternalSecret (1h 주기 동기화)
              └─ K8s Secret (stockops-secret) 자동 생성
                   └─ 파드 환경변수 주입
```

> destroy/재apply 후 `stockops-secret` 수동 생성 불필요 (ESO 자동 복구).

---

## IoT 센서 파이프라인

```
온프레미스 센서 (sensormqtt.ithans.com)
    └─ Mosquitto 브리지 (TLS:8883) — 설정 대기 중
         └─ AWS IoT Core (sensimul/sites/+/sensors/+)
              └─ IoT Rule → SQS (stockops-sensor-data)
```

현장 ID: `TEST_INDOOR_01` / 센서 7종: TEMP, HUM, PM25, PM10, PRESSURE, DOOR, PRESENCE

---

## 배포 방법

### 사전 준비
- AWS CLI 자격증명 (`aws sso login --profile siseon`)
- kubectl, terraform 설치
- 각 리전 `terraform.tfvars` 생성 (jwt_secret, db_username, db_password)

### 배포 순서

```powershell
# 1. 서울
cd seoul
terraform apply --% -auto-approve -target=module.seoul_vpc -target=module.seoul_alb -target=module.seoul_eks -target=module.seoul_db -target=module.seoul_ecr
aws eks update-kubeconfig --region ap-northeast-2 --name seoul-cluster --profile siseon
terraform apply -auto-approve

# 2. 오하이오
cd ..\ohio
terraform apply --% -auto-approve -target=module.ohio_vpc -target=module.ohio_alb -target=module.ohio_eks -target=aws_db_instance.ohio_replica
aws eks update-kubeconfig --region us-east-2 --name ohio-cluster --profile siseon
terraform apply -auto-approve

# 3. 글로벌 (GA)
cd ..\global
terraform init
terraform apply -auto-approve
```

> Cross-Region Replica(오하이오 RDS)는 생성에 약 25분 소요.

### 애플리케이션 이미지 배포 (GitHub Actions)

인프라(ECR) 생성 후 Stockops-Application 레포에서 이미지를 빌드/푸시한다.

```powershell
# main 브랜치 push 또는 수동 트리거
gh workflow run deploy.yml
```

- GitHub Actions가 OIDC로 인증 → 4개 이미지 빌드 → 서울 ECR push
- 서울 ECR → 오하이오 ECR 자동 replication
- 이어서 `kubectl rollout restart`로 EKS 파드 재배포
- 이미지가 ECR에 올라오면 `ImagePullBackOff` 상태였던 Pod가 자동으로 다시 pull → Running

### 검증

```powershell
kubectl get pods -n stockops
terraform output global_accelerator_dns
```

### 초기 로그인 계정
- 이메일: `admin@stockops.com`
- 비밀번호: `admin123`

---

## 종료 (destroy)

역순으로 진행 (global → ohio → seoul).

```powershell
# 1. 글로벌
cd global
terraform destroy -auto-approve

# 2. 오하이오 (TGB 먼저)
cd ..\ohio
terraform destroy --% -auto-approve -target=kubectl_manifest.client_tgb -target=kubectl_manifest.admin_tgb -target=kubectl_manifest.api_tgb -target=kubectl_manifest.ai_tgb
terraform destroy -auto-approve

# 3. 서울 (TGB 먼저)
cd ..\seoul
terraform destroy --% -auto-approve -target=kubectl_manifest.client_tgb -target=kubectl_manifest.admin_tgb -target=kubectl_manifest.api_tgb -target=kubectl_manifest.ai_tgb
terraform destroy -auto-approve
```

> Global Accelerator는 ALB를 참조하므로 반드시 먼저 삭제.
> 오하이오 RDS(Replica)는 서울 RDS보다 먼저 삭제.

### destroy 후 잔재 확인

```powershell
aws ec2 describe-nat-gateways --filter "Name=state,Values=available" --query "NatGateways[*].NatGatewayId" --output table --region ap-northeast-2
aws ec2 describe-nat-gateways --filter "Name=state,Values=available" --query "NatGateways[*].NatGatewayId" --output table --region us-east-2
aws iam list-roles --query "Roles[?contains(RoleName, 'seoul') || contains(RoleName, 'ohio') || contains(RoleName, 'stockops')].RoleName" --output table
```

> destroy 후 재apply 시 IoT 인증서 새로 발급 → 온프레미스 브리지 재설정 필요.

---

## 로드맵

- [x] VPC + EKS + ALB + RDS + ECR 배포 (서울)
- [x] GitHub Actions OIDC 전환 (액세스 키 제거)
- [x] IoT Core + SQS 파이프라인 구축
- [x] S3 Terraform backend + state 중앙화 (seoul/ohio/global 분리)
- [x] Secrets Manager + ESO 연동 (시크릿 자동화)
- [x] ArgoCD 설치
- [x] 멀티 리전 (오하이오) 풀스택 + ECR replication
- [x] Cross-Region RDS Read Replica
- [x] Global Accelerator
- [ ] Route 53 + ACM — 도메인 연결 + 호스트 기반 라우팅 (admin/client 분리)
- [ ] WAF — ALB/GA 앞단 보안
- [ ] ArgoCD 앱 구성 (GitOps CD)
- [ ] IoT 브리지 연결 확인
- [ ] 서울 RDS Multi-AZ 활성화
- [ ] Azure 트랜잭션 로그 백업 (3차 방어)
- [ ] Observability 스택

자세한 아키텍처는 `ARCHITECTURE.md`, AWS 리소스 목록은 `AWS_RESOURCES.md` 참고.
