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
- **AWS 오하이오**: 미국 영업팀 대상 서비스 (멀티 리전 확장 예정)
- **온프레미스(한국)**: 센터/창고. 온도 센서 데이터 수집
- **Azure 서울**: 백업 데이터 + 상시 로그 저장 (재해 복구용)

**데이터**: AWS RDS Multi-AZ / 서울(Master) ↔ 오하이오(Slave) 동기화, 미국은 읽기 전용 / Azure에 백업·로그  
**트래픽**: Global Accelerator 지연 기반 라우팅 (한국→서울, 미국→오하이오), 리전 장애 시 페일오버  
**보안**: 미국 영업팀은 최소 권한으로 앱/DB 접근 (본사 영향 차단)

---

## 레포 구성

| 레포 | 내용 |
|------|------|
| **Stockops-Infra** | Terraform IaC (modules + seoul, 추후 ohio) |
| **Stockops-Application** | 앱 모노레포 (admin-web, ai-module, api-server, client-web) + GitHub Actions |

### 애플리케이션 컴포넌트

| 컴포넌트 | 기술 | 포트 | ALB 경로 |
|----------|------|------|----------|
| client-web | React + nginx | 80 | `/` (default) |
| admin-web | React + nginx | 80 | `/admin` |
| api-server | Spring Boot 3.2.12 / Java 21 | 8080 | `/api` |
| ai-module | FastAPI | 8000 | `/ai` |

---

## 인프라 구성 현황

### 모듈 구조

```
modules/
├── vpc/            # VPC + 3-tier 서브넷 (public / private-app / private-db)
├── eks/            # EKS 클러스터 (seoul-cluster v1.30, t3.medium×2) + OIDC Provider
├── alb/            # ALB + 경로 기반 Target Group (/, /admin, /api, /ai)
├── db/             # RDS PostgreSQL 16 (Multi-AZ)
├── ecr/            # ECR 리포 × 4 (api, ai, admin-web, client-web)
├── github-oidc/    # GitHub Actions OIDC Provider + IAM Role
└── iot/            # IoT Thing + 인증서 + 정책 + Rule + SQS + DLQ
```

### 배포된 AWS 리소스

| 리소스 | 상세 |
|--------|------|
| VPC | 10.0.0.0/16, 서울 2-AZ (2a/2c) |
| EKS | seoul-cluster v1.30, t3.medium×2 |
| ALB | 경로 기반 라우팅 (/, /admin, /api, /ai) |
| RDS | PostgreSQL 16, db.t3.micro, stockops DB |
| ECR | 4개 리포 (api / ai / admin-web / client-web) |
| IoT Core | Thing + 인증서 + SQS Rule |
| SQS | stockops-sensor-data / stockops-sensor-data-dlq |
| Secrets Manager | stockops/app (JWT, DB 자격증명) |
| S3 | siseon-terraform-state (Terraform state 백엔드) |

### CI/CD

```
GitHub Actions (CI)
    └─ 코드 push → 이미지 빌드 → ECR push
         └─ OIDC 인증 (액세스 키 없음, role-to-assume 방식)

ArgoCD (CD) — 예정
    └─ GitOps 방식 배포
```

### 시크릿 관리 (ESO)

```
Secrets Manager (stockops/app)
    └─ ESO Controller (ClusterSecretStore)
         └─ ExternalSecret (1h 주기 동기화)
              └─ K8s Secret (stockops-secret) 자동 생성
                   └─ 파드 환경변수 주입
```

> ESO IRSA로 Secrets Manager 접근 권한 부여. `terraform.tfvars`에 실제 값 관리, Git 비추적.

### IoT 센서 파이프라인

```
온프레미스 센서 (sensormqtt.ithans.com)
    └─ Mosquitto 브리지 (TLS:8883) — 설정 대기 중
         └─ AWS IoT Core
              └─ IoT Rule (sensimul/sites/+/sensors/+)
                   └─ SQS (stockops-sensor-data)
```

현장 ID: `TEST_INDOOR_01` / 센서 7종: TEMP, HUM, PM25, PM10, PRESSURE, DOOR, PRESENCE

---

## 배포 방법

### 사전 준비

- AWS CLI 자격증명 설정 (`aws sso login --profile siseon`)
- kubectl, terraform 설치
- `seoul/terraform.tfvars` 생성:

```hcl
jwt_secret  = "<랜덤 32자 이상>"
db_username = "<DB 유저>"
db_password = "<DB 비밀번호>"
```

### 1. 인프라 배포

```powershell
cd seoul

# (A) 클러스터가 이미 있는 경우 — 한 방에
terraform apply -auto-approve

# (B) 완전 처음(클러스터 없음) — 단계 분리
terraform apply --% -auto-approve -target=module.seoul_vpc -target=module.seoul_alb -target=module.seoul_eks -target=module.seoul_db -target=module.seoul_ecr
aws eks update-kubeconfig --region ap-northeast-2 --name seoul-cluster --profile siseon
terraform apply -auto-approve
```

> `wait_for_rollout = false` 설정으로 deployment는 이미지가 없어도 apply가 멈추지 않는다.

### 2. kubeconfig 업데이트

```powershell
aws eks update-kubeconfig --name seoul-cluster --region ap-northeast-2 --profile siseon
```

### 3. K8s Secret 확인

ESO가 자동으로 `stockops-secret`을 생성한다. 정상 동작 여부 확인:

```powershell
kubectl get externalsecret -n stockops
kubectl get secret stockops-secret -n stockops
```

> `STATUS: SecretSynced` 확인. 이전처럼 `kubectl create secret` 수동 생성 불필요.

### 4. 애플리케이션 이미지 배포 (GitHub Actions)

ECR 리포가 생성된 뒤, Stockops-Application의 GitHub Actions로 이미지를 빌드/푸시한다.

```powershell
# main 브랜치 push 또는 수동 트리거
gh workflow run deploy.yml
```

이미지가 ECR에 올라오면 ImagePullBackOff 상태였던 Pod가 자동으로 다시 pull → Running.

### 5. 검증

```powershell
kubectl get pods -n stockops
kubectl get targetgroupbinding -n stockops
# api 헬스체크
kubectl exec -it <api-pod> -n stockops -- curl -s localhost:8080/actuator/health
```

ALB DNS 확인:

```powershell
aws elbv2 describe-load-balancers --names seoul-alb --query "LoadBalancers[0].DNSName" --output text
```

### 6. 초기 로그인 계정

앱 기동 시 `AuthDataLoader`가 admin 계정을 자동 시드한다.

- 이메일: `admin@stockops.com`
- 비밀번호: `admin123`

테스트 계정(manager/staff/user)은 `STOCKOPS_TEST_ACCOUNTS_PASSWORD` 환경변수 설정 시에만 생성된다.

---

## 종료 (destroy)

```powershell
# TGB 먼저 (LBC 살아있을 때)
terraform destroy --% -auto-approve -target=kubectl_manifest.client_tgb -target=kubectl_manifest.admin_tgb -target=kubectl_manifest.api_tgb -target=kubectl_manifest.ai_tgb

# 전체
terraform destroy -auto-approve

# destroy가 막히면 TGB 수동 삭제 후 재시도
kubectl delete targetgroupbinding --all -n stockops
```

### destroy 후 잔재 확인 (중요)

```powershell
# IAM Role — Terraform이 추적 못 하면 재구축 시 "already exists" 발생
aws iam list-roles --query "Roles[?contains(RoleName, 'seoul')].RoleName" --output table

# 과금 리소스
aws ec2 describe-nat-gateways --filter "Name=state,Values=available" --query "NatGateways[*].NatGatewayId" --output table
aws rds describe-db-instances --query "DBInstances[*].DBInstanceIdentifier" --output table
aws elbv2 describe-load-balancers --query "LoadBalancers[*].LoadBalancerName" --output table
```

남을 수 있는 IAM: `seoul-eks-cluster-role`, `seoul-eks-node-role`, `seoul-lbc-role`, `stockops-eso-role`, `github-actions-ecr-push`, 커스텀 정책 `seoul-lbc-policy`. 정책을 detach 후 role 삭제.

> **주의**: destroy 후 재apply 시 IoT 인증서가 새로 발급된다. 온프레미스 브리지 설정에 사용한 인증서가 무효화되므로 재추출 후 재전달 필요.

---

## 로드맵

- [x] VPC + EKS + ALB + RDS + ECR 배포
- [x] GitHub Actions OIDC 전환 (액세스 키 제거)
- [x] IoT Core + SQS 파이프라인 구축
- [x] S3 Terraform backend + state 중앙화
- [x] Secrets Manager + ESO 연동 (시크릿 자동화)
- [ ] Route 53 + ACM — 도메인 연결 + admin 서브패스 쿠키 문제 해결
- [ ] ArgoCD — GitOps CD 구성
- [ ] IoT 브리지 연결 확인 (온프레미스 Mosquitto → IoT Core)
- [ ] 멀티 리전 (오하이오) + ECR replication
- [ ] Global Accelerator
- [ ] Observability 스택

자세한 아키텍처는 `ARCHITECTURE.md`, AWS 리소스 목록은 `AWS_RESOURCES.md` 참고.
