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

## 배포 방법

### 사전 준비
- AWS CLI 자격증명 설정
- kubectl, terraform 설치
- `terraform.tfvars`에 `db_username`, `db_password`, `jwt_secret` 등 설정

### 1. 인프라 배포

```powershell
cd seoul

# 최초 구축 시: EKS 클러스터가 없으면 provider 연결 문제로
# kubernetes_manifest/kubectl_manifest가 plan에서 실패할 수 있음.
# 그 경우 인프라 먼저 → kubeconfig → 전체 순으로 분리 실행.

# (A) 클러스터가 이미 있는 경우 — 한 방에
terraform apply -auto-approve

# (B) 완전 처음(클러스터 없음) — 단계 분리
terraform apply --% -auto-approve -target=module.seoul_vpc -target=module.seoul_alb -target=module.seoul_eks -target=module.seoul_db -target=module.seoul_ecr
aws eks update-kubeconfig --region ap-northeast-2 --name seoul-cluster
terraform apply -auto-approve
```

> `wait_for_rollout = false` 설정으로 deployment는 이미지가 없어도 apply가 멈추지 않는다.

### 2. Kubernetes Secret 생성

```powershell
kubectl create secret generic stockops-secret `
  --from-literal=JWT_SECRET="<랜덤32자이상>" `
  --from-literal=DB_USERNAME="<DB유저>" `
  --from-literal=DB_PASSWORD="<DB비번>" `
  -n stockops
```

### 3. 애플리케이션 이미지 배포 (GitHub Actions)

ECR 리포가 생성된 뒤, Stockops-Application의 GitHub Actions로 이미지를 빌드/푸시한다.

```powershell
# main 브랜치 push 또는 수동 트리거
gh workflow run deploy.yml
```

이미지가 ECR에 올라오면 ImagePullBackOff 상태였던 Pod가 자동으로 다시 pull → Running.

### 4. 검증

```powershell
kubectl get pods -n stockops
kubectl get targetgroupbinding -n stockops
# api 헬스체크
kubectl exec -it <api-pod> -n stockops -- curl -s localhost:8080/actuator/health
```

ALB DNS로 접속:
```powershell
aws elbv2 describe-load-balancers --names seoul-alb --query "LoadBalancers[0].DNSName" --output text
```

### 5. 초기 로그인 계정

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

남을 수 있는 IAM: `seoul-eks-cluster-role`, `seoul-eks-node-role`, `seoul-lbc-role`, 커스텀 정책 `seoul-lbc-policy`. 정책을 detach 후 role 삭제.

---

## 추가 예정 (로드맵)

- **호스트 분리**: Route 53 + ACM으로 `admin.도메인` / `client.도메인` 분리 → 서브패스 쿠키 문제 근본 해결
- **멀티 리전**: 오하이오 리전 확장 + ECR replication
- **Secrets Manager**: ESO(설치됨) 연동으로 DB/JWT 시크릿 자동 동기화, RDS `manage_master_user_password`
- **온프레미스 연동**: Site-to-Site VPN
- **센서 파이프라인**: IoT Core → SQS → 백엔드 분석
- **기타**: S3, Global Accelerator, Observability 스택

자세한 아키텍처는 `ARCHITECTURE.md`, AWS 리소스 목록은 `AWS_RESOURCES.md` 참고.