# StockOps AWS 리소스 인벤토리 (멀티 리전)

> 현재까지 구축된 AWS 리소스 전체 목록
> 계정: `448768137813`
> 리전: 서울 `ap-northeast-2` + 오하이오 `us-east-2`
> IaC: Terraform (`modules` + `seoul` + `ohio` + `global`)
> Terraform State: S3 (`siseon-terraform-state/infra/{seoul,ohio,global}/terraform.tfstate`)

---

## 0. 리전 요약

| 구분 | 서울 (ap-northeast-2) | 오하이오 (us-east-2) |
|------|----------------------|---------------------|
| 역할 | 본사, 한국 사용자 (풀스택) | 미국 영업팀 (풀스택 미러) |
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 |
| EKS | seoul-cluster | ohio-cluster |
| RDS | PostgreSQL 16 (Master) | Read Replica |
| ECR | 원본 4개 | replication 자동 복제 |
| IoT/SQS | ✅ | — |

**글로벌**: Global Accelerator (서울 + 오하이오 ALB)

---

## 1. 네트워크 (modules/vpc)

### 서울 VPC (10.0.0.0/16) / 오하이오 VPC (10.1.0.0/16)

| 계층 | 서울 | 오하이오 | 용도 |
|------|------|----------|------|
| Public | 10.0.1~2.0/24 | 10.1.1~2.0/24 | ALB, NAT GW |
| Private App | 10.0.11~12.0/24 | 10.1.11~12.0/24 | EKS 노드, Pod |
| Private DB | 10.0.21~22.0/24 | 10.1.21~22.0/24 | RDS |

각 리전: IGW, NAT GW, 라우팅 테이블 (public/private app/private db)

> NAT Gateway 시간당 과금 — 양 리전 모두 주의

---

## 2. 로드밸런서 (modules/alb)

### ALB (서울: seoul-alb / 오하이오: ohio-alb)
- 리스너: HTTP :80
- 타입: Application Load Balancer (public 서브넷)

### 리스너 규칙 (양 리전 동일)

| 우선순위 | 경로 | 대상 그룹 |
|----------|------|-----------|
| 85 | `/admin`, `/admin/*` | {region}-admin-tg |
| 90 | `/api`, `/api/*` | {region}-spring-tg |
| 100 | `/ai`, `/ai/*` | {region}-fastapi-tg |
| default | 그 외 | {region}-frontend-tg |

### 대상 그룹 (각 리전 4개, targetType: ip)

| 이름 | 포트 | 헬스체크 |
|------|------|----------|
| frontend-tg | 80 | `/` |
| admin-tg | 80 | `/` |
| spring-tg | 8080 | `/actuator/health` |
| fastapi-tg | 8000 | `/health` |

---

## 3. EKS (modules/eks)

### 클러스터 (서울: seoul-cluster / 오하이오: ohio-cluster)
- 버전: 1.30
- 노드: t3.medium × 2 (min 2 / max 4)
- 엔드포인트: private + public

### IAM Role

| Role | 리전 | 용도 |
|------|------|------|
| `seoul-eks-cluster-role` / `ohio-eks-cluster-role` | 각 | 컨트롤플레인 |
| `seoul-eks-node-role` / `ohio-eks-node-role` | 각 | 워커 노드 |
| `seoul-lbc-role` / `ohio-lbc-role` | 각 | LB Controller (IRSA) |
| `stockops-eso-role` | 서울 | ESO (IRSA) |
| `ohio-eso-role` | 오하이오 | ESO (IRSA, 예정) |
| `github-actions-ecr-push` | 글로벌 | GitHub Actions OIDC |

### IRSA / OIDC
- 각 EKS 클러스터별 OIDC Provider
- LBC: `kube-system/aws-load-balancer-controller`
- ESO: `external-secrets/external-secrets`
- GitHub Actions: `token.actions.githubusercontent.com` (계정당 1개, 서울에 생성)

---

## 4. RDS (modules/db + ohio replica)

### 서울 — Master
- 식별자: `seoul-rds-postgres`
- 엔진: PostgreSQL 16, db.t4g.micro
- 스토리지: gp3 20GB (최대 100GB)
- DB명: `stockops`, 백업 7일, 퍼블릭 비활성
- StorageEncrypted: false

### 오하이오 — Read Replica
- 식별자: `ohio-rds-postgres`
- `replicate_source_db` = `arn:aws:rds:ap-northeast-2:448768137813:db:seoul-rds-postgres`
- 서울 데이터 실시간 복제 (검증 완료: 서울 상품 추가 → 오하이오 반영 확인)
- 장애 시 Promote → Master 승격

> Replica는 username/password/db_name 지정 불가 (소스에서 자동 복제)

---

## 5. ECR (modules/ecr + replication)

### 서울 — 원본 4개 리포

| 리포지토리 | 이미지 |
|-----------|--------|
| `stockops-api` | Spring Boot |
| `stockops-ai` | FastAPI |
| `stockops-admin-web` | 관리자 React |
| `stockops-client-web` | 사용자 React |

레지스트리: `448768137813.dkr.ecr.ap-northeast-2.amazonaws.com`

### Replication
- 서울 → 오하이오(us-east-2) 자동 복제
- 필터: prefix `stockops`
- 오하이오 레지스트리: `448768137813.dkr.ecr.us-east-2.amazonaws.com`

---

## 6. GitHub Actions OIDC (modules/github-oidc)

- OIDC Provider: `token.actions.githubusercontent.com`
- IAM Role: `github-actions-ecr-push`
- 허용 브랜치: `main`
- 권한: ECR Push (4개 리포), EKS DescribeCluster
- aws-auth ConfigMap에 `system:masters`로 등록 (Terraform 관리)

---

## 7. IoT Core (modules/iot — 서울만)

| 리소스 | 상세 |
|--------|------|
| IoT Thing | `mosquitto-bridge` |
| 인증서 | X.509 (sensitive output) |
| IoT 정책 | Connect + Publish 허용 |
| IoT Rule | `sensimul/sites/+/sensors/+` → SQS |
| SQS | `stockops-sensor-data` |
| DLQ | `stockops-sensor-data-dlq` |
| 엔드포인트 | `a2ie1b3xp2emgi-ats.iot.ap-northeast-2.amazonaws.com` |

> destroy 후 재apply 시 인증서 새로 발급 → 재추출/재전달 필요

---

## 8. Secrets Manager

| 리소스 | 상세 |
|--------|------|
| 시크릿 | `stockops/app` (서울, 오하이오 예정) |
| 키 | `JWT_SECRET`, `DB_USERNAME`, `DB_PASSWORD` |
| 복구 기간 | 0일 (즉시 삭제, dev) |
| 접근 | `stockops-eso-role` / `ohio-eso-role` (IRSA) |

> 실제 값은 `terraform.tfvars` 관리, Git 비추적

---

## 9. Global Accelerator (global)

| 리소스 | 상세 |
|--------|------|
| Accelerator | `stockops-global-accelerator` |
| DNS | `a14ff4d30e6eff6d4.awsglobalaccelerator.com` |
| 고정 IP | `166.117.94.157`, `76.223.25.145` |
| 리스너 | TCP:80 |
| 엔드포인트 그룹 | 서울 ALB + 오하이오 ALB (각 traffic_dial 100%) |
| 헬스체크 | HTTP `/`, 30초 간격, threshold 3 |

> 관리 리전 us-west-2. ALB ARN은 terraform_remote_state로 동적 참조.

---

## 10. S3

| 버킷 | 용도 |
|------|------|
| `siseon-terraform-state` | Terraform state (infra/seoul, infra/ohio, infra/global) |

- 버저닝: 활성화

---

## 11. Kubernetes 리소스 (각 리전 kubernetes.tf)

### 네임스페이스
- `stockops` (앱), `external-secrets` (ESO), `kube-system` (LBC), `argocd` (서울)

### Helm Release
- `external-secrets`, `aws-load-balancer-controller`
- `argocd` (서울만, v7.7.0, ClusterIP)

### Deployment / Service (각 리전, 네임스페이스 stockops)

| Deployment | 포트 | 비고 |
|-----------|------|------|
| stockops-client-web | 80 | wait_for_rollout=false |
| stockops-admin-web | 80 | wait_for_rollout=false |
| stockops-api | 8080 | wait_for_rollout=false |
| stockops-ai | 8000 | wait_for_rollout=false |
| stockops-redis | 6379 | redis:7-alpine |

### TargetGroupBinding (kubectl_manifest, 각 리전 4개)
- client/admin/api/ai-tgb → 각 ALB TG, `targetType: ip`, `depends_on=LBC`

### ESO (kubectl_manifest)
- `ClusterSecretStore`: `stockops-secret-store`
- `ExternalSecret`: `stockops-external-secret` (1h, `stockops-secret` 자동 생성)

### 오하이오 차이점
- 이미지: 오하이오 ECR URL (`...us-east-2...`) 직접 참조
- DB URL: `aws_db_instance.ohio_replica.address` 참조
- IoT 관련 없음

---

## 12. 과금 주의 리소스 (양 리전)

| 리소스 | 과금 방식 |
|--------|-----------|
| NAT Gateway | 시간당 + 데이터 처리량 (리전당 1개) |
| RDS | 시간당 (서울 Master + 오하이오 Replica = 2개) |
| ALB | 시간당 + LCU (리전당 1개) |
| EKS 클러스터 | 시간당 $0.10 (2개) |
| EC2 노드 | 시간당 (t3.medium × 2 × 2리전 = 4대) |
| Global Accelerator | 시간당 고정 + 데이터 전송 |

destroy 후 잔재 확인:

```powershell
aws ec2 describe-nat-gateways --filter "Name=state,Values=available" --query "NatGateways[*].NatGatewayId" --output table --region ap-northeast-2
aws ec2 describe-nat-gateways --filter "Name=state,Values=available" --query "NatGateways[*].NatGatewayId" --output table --region us-east-2
aws rds describe-db-instances --query "DBInstances[*].DBInstanceIdentifier" --output table --region ap-northeast-2
aws rds describe-db-instances --query "DBInstances[*].DBInstanceIdentifier" --output table --region us-east-2
aws globalaccelerator list-accelerators --region us-west-2
aws iam list-roles --query "Roles[?contains(RoleName, 'seoul') || contains(RoleName, 'ohio') || contains(RoleName, 'stockops') || contains(RoleName, 'github-actions')].RoleName" --output table
```

---

## 13. Terraform 모듈 의존 관계

```
seoul/main.tf
├── module.seoul_vpc / alb / eks / db / ecr
└── aws_ecr_replication_configuration (서울 → 오하이오)

seoul/iam.tf       → module.github_oidc, aws_iam_role.eso
seoul/iot.tf       → module.seoul_iot
seoul/secrets.tf   → aws_secretsmanager_secret
seoul/kubernetes.tf → ESO, LBC, ArgoCD, deploy×5, TGB×4, aws-auth

ohio/main.tf
├── module.ohio_vpc / alb / eks
└── aws_db_instance.ohio_replica (서울 RDS 복제)

ohio/kubernetes.tf → LBC, deploy×5, TGB×4, aws-auth (ESO 예정)

global/main.tf
├── data.terraform_remote_state.seoul / ohio (ALB ARN 참조)
└── aws_globalaccelerator_* (accelerator, listener, endpoint_group×2)
```

---

## 14. 아직 미구축 (로드맵)

| 항목 | 우선순위 |
|------|----------|
| Route 53 + ACM (도메인 stockops.live, 호스트 분리) | 높음 |
| WAF (ALB/GA 앞단) | 중간 |
| ArgoCD 앱 구성 (GitOps CD) | 중간 |
| IoT 브리지 연결 확인 | 중간 |
| 서울 RDS Multi-AZ 활성화 | 중간 |
| 오하이오 ESO + Secrets Manager | 중간 |
| Azure 트랜잭션 로그 백업 (3차 방어) | 낮음 |
| Observability 스택 | 낮음 |

---

*최종 업데이트: 2026-06-08 / 오하이오 멀티 리전 풀스택, Cross-Region RDS Replica, Global Accelerator, ECR replication, ArgoCD 설치, state 분리(seoul/ohio/global) 완료*
