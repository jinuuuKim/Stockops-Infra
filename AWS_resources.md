# StockOps AWS 리소스 인벤토리 (멀티 리전)

> 현재까지 Terraform 으로 구축된 AWS 리소스 전체 목록
> 계정: `448768137813`
> 리전: 서울 `ap-northeast-2` + 오하이오 `us-east-2` + 글로벌(us-west-2 GA / us-east-1 CloudFront ACM·WAF)
> IaC: Terraform (`bootstrap` + `modules` + `regions/{seoul,ohio,global}` + `peering`)
> Terraform State: S3 (`siseon-terraform-state/infra/{seoul,ohio,peering,global}/terraform.tfstate`, KMS 암호화 + 네이티브 락)

---

## 0. 리전 요약

| 구분 | 서울 (ap-northeast-2) | 오하이오 (us-east-2) |
|------|----------------------|---------------------|
| 역할 | 본사, 한국 사용자 (풀스택) | 미국 영업팀 (풀스택 미러, 페일오버) |
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 |
| EKS | seoul-cluster v1.30 | ohio-cluster v1.30 |
| 노드 | 관리형 NG(t3.medium ×2) + Karpenter | 관리형 NG(t3.medium ×2) + Karpenter |
| RDS | PostgreSQL 18.4 (Master) | Read Replica |
| ECR | 2개 리포 (api, ai) | 2개 리포 (api, ai) — 리전별 독립 |
| ALB + WAF | ✅ HTTPS + REGIONAL WAF | ✅ HTTPS + REGIONAL WAF |
| IoT | ✅ SQS + Firehose 팬아웃 | SQS only (페일오버) |
| Secrets Manager + ESO | ✅ (소유) | ✅ (서울 시크릿 cross-region 참조) |
| DR 백업 | ✅ (SG/IAM/EventBridge/ECR 토대) | — |

**글로벌**: Global Accelerator(us-west-2) + Route53 + CloudFront/S3(OAC) + CloudFront ACM/WAF(us-east-1)

---

## 1. Bootstrap (state 토대 — `bootstrap/`)

| 리소스 | 상세 |
|--------|------|
| KMS Key + Alias | `alias/siseon-tfstate` (키 로테이션 ON, root 위임 정책) |
| S3 state 버킷 하드닝 | `siseon-terraform-state` — 퍼블릭 차단 + 버저닝 + 기본 SSE-KMS + 비-TLS 거부 정책 |

> bootstrap 자신은 로컬 백엔드(닭-달걀 회피). 버킷 리소스는 소유하지 않고 하위 설정만 적용.

---

## 2. 네트워크 (modules/vpc)

### 서울 VPC (10.0.0.0/16) / 오하이오 VPC (10.1.0.0/16)

| 계층 | 서울 | 오하이오 | 용도 |
|------|------|----------|------|
| Public | 10.0.1~2.0/24 | 10.1.1~2.0/24 | ALB, NAT GW |
| Private App | 10.0.11~12.0/24 | 10.1.11~12.0/24 | EKS 노드, Pod, Karpenter |
| Private DB | 10.0.21~22.0/24 | 10.1.21~22.0/24 | RDS |

각 리전: IGW, NAT GW(1개), 라우팅 테이블(public / private app / private db). 서브넷 태그: `kubernetes.io/role/elb`·`internal-elb`, `kubernetes.io/cluster/<cluster>`, `karpenter.sh/discovery`.

> NAT Gateway 시간당 + 데이터 처리 과금 — 양 리전 주의.

---

## 3. 로드밸런서 + WAF (modules/alb)

### ALB (서울: seoul-alb / 오하이오: ohio-alb)
- 리스너: HTTP :80 → HTTPS :443 (301 리다이렉트), HTTPS :443 (ACM, `ELBSecurityPolicy-TLS13-1-2-2021-06`)
- 타입: Application Load Balancer (public 서브넷)
- `idle_timeout = 120` (WebSocket/STOMP 장시간 연결 지원)

### 리스너 규칙 (양 리전 동일, HTTPS 리스너)

| 우선순위 | 경로 | 대상 그룹 |
|----------|------|-----------|
| 5 | `/ws`, `/ws/*` | {region}-spring-tg (WebSocket) |
| 10 | `/api`, `/api/*` | {region}-spring-tg |
| 20 | `/ai`, `/ai/*` | {region}-fastapi-tg |
| default | 그 외 | **fixed-response 404** |

### 대상 그룹 (각 리전 2개, targetType: ip)

| 이름 | 포트 | 헬스체크 |
|------|------|----------|
| spring-tg | 8080 | `/actuator/health` |
| fastapi-tg | 8000 | `/health` |

> 정적 프론트가 CloudFront/S3 로 이전되면서 frontend-tg / admin-tg 및 admin 호스트 룰은 제거됨.

### WAF (modules/alb/waf.tf — REGIONAL, `enable_waf = true` 양 리전)

| 우선순위 | 룰 | 액션 |
|----------|----|------|
| 1 | AWSManagedRulesCommonRuleSet | 관찰(count) |
| 2 | AWSManagedRulesKnownBadInputsRuleSet | block |
| 3 | AWSManagedRulesSQLiRuleSet | 관찰(count) |
| 4 | LoginRateLimit (`/api/v1/auth/login`, 100/5분) | block |
| 5 | RateLimit (전체, 2000/5분) | block |

- WebACL `{region}-alb-waf` ↔ ALB association, 로그 → CloudWatch `aws-waf-logs-stockops-alb-{region}` (7일).

---

## 4. EKS + 오토스케일링 (modules/eks + modules/karpenter)

### 클러스터 (서울: seoul-cluster / 오하이오: ohio-cluster)
- 버전: **1.30**, 엔드포인트: private + public
- 관리형 노드그룹: t3.medium, desired 2 / min 2 / max 4

### Karpenter (helm 1.3.3)
- NodePool: `spot` + `on-demand`, `t3.medium`/`t3.large`, amd64, AMI `al2023@latest`
- limits: cpu 8 / memory 16Gi, consolidation `WhenEmptyOrUnderutilized`(1m)
- EC2NodeClass: 서브넷/SG `karpenter.sh/discovery` 태그 셀렉터
- Spot 인터럽션 핸들링 SQS: `{cluster}-karpenter-interruption`
- Spot Service Linked Role: 서울에서 생성(계정당 1개)

### HPA
| 대상 | 메트릭 | min/max |
|------|--------|---------|
| stockops-api | CPU 60% | 1 / 4 |
| stockops-ai | CPU 60% + Memory 70% | 1 / 4 |

> metrics-server 필요.

### IAM Role

| Role | 리전 | 용도 |
|------|------|------|
| `seoul-eks-cluster-role` / `ohio-eks-cluster-role` | 각 | 컨트롤플레인 |
| `seoul-eks-node-role` / `ohio-eks-node-role` | 각 | 워커 노드 |
| `seoul-lbc-role` / `ohio-lbc-role` | 각 | LB Controller (IRSA) |
| `seoul-cluster-karpenter-role` / `ohio-cluster-karpenter-role` | 각 | Karpenter (IRSA) |
| `stockops-eso-role` / `ohio-eso-role` | 각 | ESO (IRSA) |
| `stockops-api-sqs-role` / `stockops-api-sqs-role-ohio` | 각 | api-server SQS consume (IRSA) |
| `github-actions-ecr-push` | 글로벌 | GitHub Actions OIDC |

### IRSA / OIDC
- 각 EKS 클러스터별 OIDC Provider
- LBC: `kube-system/aws-load-balancer-controller`
- ESO: `external-secrets/external-secrets`
- Karpenter: `karpenter/karpenter`
- api-server SQS: `stockops/stockops-api-sa`
- GitHub Actions: `token.actions.githubusercontent.com` (계정당 1개, 서울에 생성)

### aws-auth ConfigMap (mapRoles)
- EKS 노드 Role(`system:nodes`), Karpenter 노드 Role, GitHub Actions Role(`system:masters`), 팀원 SSO 권한셋(`AWSReservedSSO_AdministratorAccess`, `system:masters`)

---

## 5. RDS (modules/db + ohio replica)

### 서울 — Master
- 식별자: `seoul-rds-postgres`
- 엔진: **PostgreSQL 18.4**, db.t4g.micro
- 스토리지: gp3 20GB (최대 100GB)
- DB명: `stockops`, 백업 7일, 퍼블릭 비활성, `skip_final_snapshot = true`
- Multi-AZ: 코드상 주석(비용 절감) — 실배포 직전 활성화
- 파라미터 그룹 `stockops-postgres18` (family postgres18): `rds.logical_replication=1`, `shared_preload_libraries=pg_stat_statements,pg_tle,pg_cron`, `cron.database_name=stockops`

### 오하이오 — Read Replica
- 식별자: `ohio-rds-postgres`
- `replicate_source_db` = `arn:aws:rds:ap-northeast-2:448768137813:db:seoul-rds-postgres`
- 서울 데이터 실시간 복제, 장애 시 Promote → Master 승격
- 백업 7일, 퍼블릭 비활성, `skip_final_snapshot = true`

> Replica 는 username/password/db_name 지정 불가(소스에서 자동 복제). Cross-Region Replica 생성에 ~25분.

---

## 6. ECR (modules/ecr — 리전별 독립)

### 각 리전 2개 리포 (서울 + 오하이오 동일)

| 리포지토리 | 이미지 |
|-----------|--------|
| `stockops-api` | Spring Boot |
| `stockops-ai` | FastAPI |

- 서울: `448768137813.dkr.ecr.ap-northeast-2.amazonaws.com`
- 오하이오: `448768137813.dkr.ecr.us-east-2.amazonaws.com`
- 설정: `MUTABLE`, `scan_on_push`, KMS 암호화, lifecycle(최신 10개 유지), `force_delete`
- **CRR(Cross-Region Replication) 미사용** — CI 가 양 리전에 직접 push(Option B). 복제 race 없음, 리전별 롤백 가능.

### DR 전용 (서울)
| 리포지토리 | 용도 |
|-----------|------|
| `stockops-dr-ecr` | rds-to-azure 백업 컨테이너 이미지 (`data` 참조) |

---

## 7. GitHub Actions OIDC (modules/github-oidc)

- OIDC Provider: `token.actions.githubusercontent.com`
- IAM Role: `github-actions-ecr-push`
- 허용 브랜치: `main` (org `jinuuuKim`, repo `Stockops-Application`)
- 권한: ECR Push (서울 2개 + 오하이오 2개 리포 ARN), EKS DescribeCluster
- aws-auth ConfigMap 에 `system:masters` 등록 (Terraform 관리)

---

## 8. IoT Core (modules/iot — 서울)

| 리소스 | 상세 |
|--------|------|
| IoT Thing | `mosquitto-bridge` |
| 인증서 | X.509 (`var.iot_certificate_arn` 외부 참조 — destroy 후 유지) |
| IoT 정책 | `iot:Connect`(client/mosquitto-bridge-seoul) + `iot:Publish`(topic/sensimul/sites/*) |
| IoT Rule | `stockops_sensor_fanout` — `SELECT *, topic() as mqtt_topic FROM 'sensimul/sites/+/sensors/+'` |
| 팬아웃 ① | → SQS `stockops-sensor-data` (실시간, 1일 보관) / 실패 시 DLQ `stockops-sensor-data-dlq` (14일) |
| 팬아웃 ② | → Kinesis Firehose `stockops-sensor-history` → S3 `stockops-sensor-data` |
| Firehose 설정 | GZIP, 15분(900s)/5MB 버퍼, 날짜 파티션 `sensors/year=/month=/day=/`, 에러 prefix |
| 엔드포인트 | `a2ie1b3xp2emgi-ats.iot.ap-northeast-2.amazonaws.com` |
| IAM | `iot-sensor-rule-role`(SQS Send + Firehose Put), `stockops-firehose-role`(S3 쓰기) |

### 오하이오 IoT (페일오버 — SQS only)
- IoT Thing `mosquitto-bridge`(us-east-2 인증서), SQS `stockops-sensor-data` + DLQ, Rule `stockops_sensor_fanout`(SQS만, Firehose 없음), `ohio-iot-sensor-rule-role`
- 엔드포인트: `a2ie1b3xp2emgi-ats.iot.us-east-2.amazonaws.com`

> destroy 후 재apply 시에도 인증서는 외부 참조라 유지(브리지 재설정 불필요). S3 버킷(`stockops-sensor-data`)은 `data` 참조(콘솔 생성).

---

## 9. Secrets Manager (서울 소유)

| 리소스 | 상세 |
|--------|------|
| 시크릿 | `stockops/app` (서울 소유, 오하이오가 cross-region 참조) |
| 키 | `JWT_SECRET`, `DB_USERNAME/PASSWORD`, `SPRING_MAIL_PASSWORD`, AI 키류(`GEMINI_API_KEY`, `AI_MODULE_API_KEY`, `STOCKOPS_AI_SERVICE_API_KEY`), AWS 키, Bedrock/Vertex ID류 |
| 복구 기간 | 0일 (즉시 삭제, dev) |
| 접근 | `stockops-eso-role` / `ohio-eso-role` (IRSA) |

> 실제 값은 `terraform.tfvars`(`.gitignore`) 관리, 변수 `sensitive = true`. 오하이오 ESO 정책은 `terraform_remote_state.seoul.outputs.stockops_secret_arn` 참조.

---

## 10. Global Accelerator (global)

| 리소스 | 상세 |
|--------|------|
| Accelerator | `stockops-global-accelerator` (IPV4, us-west-2 관리) |
| 리스너 | TCP:80 + TCP:443 |
| 엔드포인트 그룹 | **서울(http/https) only** — `traffic_dial 100%`, `client_ip_preservation_enabled = true` |
| 헬스체크 | HTTP/HTTPS `/`, 30초 간격, threshold 3 |

> ALB ARN 은 `terraform_remote_state.seoul` 로 동적 참조. **오하이오 엔드포인트 그룹(`ohio_http`/`ohio_https`) 및 `terraform_remote_state.ohio`는 주석 처리 중** — Ohio 재배포 후 `regions/global/main.tf` 주석 해제 필요.
> ⚠️ GA 의 ALB 헬스 판정은 ALB 타깃 그룹 상태 기준(spring/fastapi TG 모두 healthy 필요).

---

## 11. Route53 + ACM (DNS / TLS)

### Route53 (호스팅 존 — 서울 소유)
- 존: `siseon.live`, 위임 세트 `N02295603ILJ5HVTJBLTY`
- A(Alias) 레코드: `siseon.live` → CloudFront(client), `app.siseon.live` → CloudFront(admin), `api.siseon.live` → Global Accelerator
- ACM 검증 레코드는 모두 이 존에 생성(`allow_overwrite`)

### ACM (3종)
| 인증서 | 리전 | 용도 |
|--------|------|------|
| seoul | ap-northeast-2 | 서울 ALB HTTPS (siseon.live + *.siseon.live) |
| ohio | us-east-2 | 오하이오 ALB HTTPS |
| cloudfront | us-east-1 | CloudFront (siseon.live + *.siseon.live) ※ CloudFront 는 us-east-1만 허용 |

---

## 12. CloudFront + S3 정적 프론트 (global/frontend.tf)

| 배포 | 도메인 | 오리진 |
|------|--------|--------|
| client | `siseon.live` | S3 `siseon-frontend-client` (OAC) |
| admin | `app.siseon.live` | S3 `siseon-frontend-admin` (OAC) |

- S3 버킷은 `data` 참조(사전 존재, Terraform 생성/삭제 X) + 퍼블릭 차단(PAB) + OAC 전용 버킷 정책
- CloudFront: `PriceClass_200`, `Managed-CachingOptimized`, SPA fallback(403/404 → `index.html`), TLSv1.2_2021, gzip, WAF(CLOUDFRONT) 연결
- OAC: `siseon-frontend-oac` (sigv4, signing always)

### CLOUDFRONT WAF (global/waf.tf — us-east-1)
| 우선순위 | 룰 | 액션 |
|----------|----|------|
| 1 | AWSManagedRulesCommonRuleSet | 관찰(count) |
| 2 | AWSManagedRulesAmazonIpReputationList | block |
- WebACL `stockops-cloudfront-waf`, 로그 → `aws-waf-logs-stockops-cloudfront` (7일)

---

## 13. S3 버킷 (역할별)

| 버킷 | 용도 | 관리 |
|------|------|------|
| `siseon-terraform-state` | Terraform state (KMS + 버저닝 + 락) | bootstrap 하드닝 |
| `siseon-frontend-client` | client 정적 자산 | `data` 참조 (CI s3 sync) |
| `siseon-frontend-admin` | admin 정적 자산 | `data` 참조 (CI s3 sync) |
| `stockops-sensor-data` | IoT 센서 이력 (Firehose) | `data` 참조 |
| `stockops-rds-backup-448768137813` | DR RDS 백업 | `data` 참조 |

---

## 14. DR 백업 (seoul/dr.tf — 시온님 설계)

| 리소스 | 상세 |
|--------|------|
| SG | `seoul-dr-backup-sg` (443 outbound, 5432 to RDS) + DB SG 인바운드 허용 |
| IAM | `seoul-dr-backup-task-role`(S3 쓰기 + VPC + Basic) / `seoul-dr-reader-role`(S3 읽기 + VPC + Basic) |
| ECR | `stockops-dr-ecr` (`data`) — rds-to-azure 이미지 |
| EventBridge | `seoul-weekly-rds-backup` — `cron(0 17 ? * SUN *)` 주 1회 |
| 컨테이너 | `lambda/rds-to-azure` (AL2023 + PostgreSQL 18 client + azure-storage-blob, pg_dump\|gzip → S3 → Azure Blob) |

> **Lambda 함수 본체 + EventBridge 타깃 연결은 주석 처리(배포 대기)** — 현재는 SG/IAM/EventBridge 규칙/ECR·S3 `data` 참조까지만 프로비저닝.

---

## 15. Kubernetes 리소스 (각 리전 kubernetes.tf)

### 네임스페이스
- `stockops`(앱), `external-secrets`(ESO), `kube-system`(LBC), `karpenter`(Karpenter), `argocd`

### Helm Release
- `external-secrets`(서울), `aws-load-balancer-controller`, `argocd`(v7.7.0, ClusterIP), `karpenter`(1.3.3)

### Terraform 이 관리하는 워크로드 (네임스페이스 stockops)

| 리소스 | 비고 |
|--------|------|
| Service `stockops-api-svc`(8080) / `stockops-ai-svc`(8000) / `stockops-redis-svc`(6379) | ClusterIP |
| ServiceAccount `stockops-api-sa` | SQS IRSA 어노테이션 |
| Deployment `stockops-redis` | redis:7-alpine (api/ai Deployment 은 CI/ArgoCD 관리) |
| HPA `stockops-api-hpa` / `stockops-ai-hpa` | CPU/Memory |
| TargetGroupBinding `stockops-api-tgb` / `stockops-ai-tgb` | `targetType: ip`, depends_on=LBC |

### ESO (kubectl_manifest)
- `ClusterSecretStore`: `stockops-secret-store` (external-secrets.io/v1)
- `ExternalSecret`: `stockops-external-secret` (1h, `stockops-secret` 자동 생성)

### 오하이오 차이점
- 이미지: 오하이오 ECR URL(`...us-east-2...`) 직접 참조
- DB URL: `aws_db_instance.ohio_replica.address` 참조
- ESO: 서울 시크릿 ARN cross-region 참조 / IoT: SQS only(페일오버)

---

## 16. 과금 주의 리소스 (양 리전)

| 리소스 | 과금 방식 |
|--------|-----------|
| NAT Gateway | 시간당 + 데이터 처리 (리전당 1개) |
| RDS | 시간당 (서울 Master + 오하이오 Replica = 2개) |
| ALB | 시간당 + LCU (리전당 1개) |
| EKS 클러스터 | 시간당 $0.10 (2개) |
| EC2 노드 | 관리형 NG(t3.medium ×2 ×2리전) + Karpenter 동적 노드(Spot 우선) |
| Global Accelerator | 시간당 고정 + 데이터 전송 |
| Firehose / SQS / Kinesis | 처리량 기반 |
| CloudFront | 데이터 전송 + 요청 (PriceClass_200) |
| WAF | WebACL/룰 + 요청 (REGIONAL 2 + CLOUDFRONT 1) |

destroy 후 잔재 확인:

```powershell
aws ec2 describe-nat-gateways --filter "Name=state,Values=available" --query "NatGateways[*].NatGatewayId" --output table --region ap-northeast-2
aws ec2 describe-nat-gateways --filter "Name=state,Values=available" --query "NatGateways[*].NatGatewayId" --output table --region us-east-2
aws rds describe-db-instances --query "DBInstances[*].DBInstanceIdentifier" --output table --region ap-northeast-2
aws rds describe-db-instances --query "DBInstances[*].DBInstanceIdentifier" --output table --region us-east-2
aws globalaccelerator list-accelerators --region us-west-2
aws cloudfront list-distributions --query "DistributionList.Items[*].DomainName" --output table
aws iam list-roles --query "Roles[?contains(RoleName, 'seoul') || contains(RoleName, 'ohio') || contains(RoleName, 'stockops') || contains(RoleName, 'github-actions')].RoleName" --output table
```

---

## 17. Terraform 모듈 의존 관계

```
bootstrap/              → KMS + state 버킷 하드닝 (로컬 백엔드)

regions/seoul/main.tf
├── module.seoul_vpc / alb(+WAF, idle_timeout=120) / eks / karpenter / db / ecr(×2)
regions/seoul/dns.tf      → Route53 zone(소유) + 서울 ACM
regions/seoul/iam.tf      → module.github_oidc
regions/seoul/iot.tf      → module.seoul_iot(SQS+Firehose) + api SQS IRSA
regions/seoul/secrets.tf  → Secrets Manager + ESO IRSA
regions/seoul/dr.tf       → DR SG/IAM/EventBridge/ECR·S3 data (Lambda 주석)
regions/seoul/kubernetes.tf → ESO/LBC/ArgoCD/Karpenter helm, svc×3, redis, HPA×2, TGB×2, aws-auth

regions/ohio/main.tf
├── module.ohio_vpc / alb(+WAF, idle_timeout=120) / eks / karpenter / ecr(×2)
├── aws_db_instance.ohio_replica (서울 RDS 복제)
regions/ohio/dns.tf       → 오하이오 ACM (서울 zone 참조)
regions/ohio/iot.tf       → SQS(페일오버) + api SQS IRSA
regions/ohio/secrets.tf   → ESO IRSA (서울 시크릿 ARN 참조)
regions/ohio/kubernetes.tf → LBC/ArgoCD/Karpenter helm, svc×3, redis, HPA×2, TGB×2, aws-auth

peering/main.tf           → Seoul↔Ohio VPC 피어링·수락·양방향 라우트 (remote_state 참조, 하드코딩 없음)

regions/global/main.tf    → GA(listener×2, endpoint group×2 서울only — Ohio 주석) — seoul ALB ARN 참조
regions/global/acm.tf     → CloudFront ACM (us-east-1)
regions/global/dns.tf     → Route53 A(Alias) ×3
regions/global/frontend.tf → CloudFront×2 + S3(OAC) data + 버킷 정책
regions/global/waf.tf     → CLOUDFRONT WAF
```

---

*최종 업데이트: 2026-06-29 / ALB idle_timeout=120s 추가, GA Ohio 엔드포인트 그룹 주석 처리(서울 only, 2 endpoint groups), peering/ 모듈 및 state 반영, 디렉토리 경로 regions/ 정정*
