# 🛒 StockOps - 식품 ERP 멀티 클라우드 인프라

![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)
![CloudFront](https://img.shields.io/badge/CloudFront-%23A166FF.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-%23316192.svg?style=for-the-badge&logo=postgresql&logoColor=white)
![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/github%20actions-%232088FF.svg?style=for-the-badge&logo=githubactions&logoColor=white)

> **팀명**: 시선 (SysSun — System Surveillance & Unified Network)
> **주제**: AX 환경을 위한 ERP 솔루션 기반 멀티 하이브리드 클라우드 인프라 자동화 및 Observability 체계 구축

StockOps는 K-Food 수출 기업(예: 비비고 만두)을 모델로 한 ERP/WMS 솔루션이다. 서울 본사가 운영을 총괄하고 미국 영업팀이 현지 영업을 지원하며, 멀티 리전·하이브리드 클라우드 위에서 동작한다.

> **도메인**: `siseon.live`
> **정적 프론트(client/admin)는 CloudFront + S3, 동적 API/WS/AI는 Global Accelerator → ALB → EKS 의 "공존(coexistence) 구조"** 로 분리되어 있다.

---

## 시나리오

- **AWS 서울**: 본사. 한국 사용자 대상 메인 서비스 (풀스택)
- **AWS 오하이오**: 미국 영업팀 대상 서비스 (멀티 리전 풀스택 미러)
- **온프레미스(한국)**: 센터/창고. 센서 데이터 수집
- **Azure 서울**: 백업 데이터 + 상시 로그 저장 (재해 복구용, 예정)

**데이터**: 3단계 방어 — Multi-AZ(1차) + Cross-Region Replica(2차) + Azure 백업(3차, 예정)
**트래픽**: 정적은 CloudFront 엣지 캐시, 동적은 Global Accelerator 지연 기반 라우팅(한국→서울, 미국→오하이오) + 리전 장애 시 페일오버
**보안**: 미국 영업팀은 최소 권한으로 앱/DB 접근 (본사 영향 차단), S3는 OAC 전용(퍼블릭 차단)

> ### 📌 현재 배포 상태
> - **서울 단일 리전 + 글로벌(CloudFront/GA/Route53)** 가동 중. 도메인 연결·CORS·정적 프론트 전환까지 검증 완료.
> - **IoT 센서 → SQS → api-server → Redis → 웹 실시간 표시 경로 E2E 검증 완료** (2026-06-15). 도어 센서 20개 + 온도 센서 1개 실데이터 표시 확인.
> - **오하이오는 비용 절감차 일시 토글 off** — `global` 의 `terraform_remote_state.ohio` + 오하이오 GA 엔드포인트 그룹(`ohio_http`/`ohio_https`) 을 주석/`enable_ohio` 플래그로 제어. 재활성화 시 오하이오 apply 후 `global` re-apply.

---

## 레포 구성

| 레포 | 내용 |
|------|------|
| **Stockops-Infra** | Terraform IaC (modules + seoul + ohio + global, state 분리) |
| **Stockops-Application** | 앱 모노레포 (포크 서브모듈: admin-web, ai-module, api-server, client-web, sensimul) + GitHub Actions |

> `Stockops-Application` 은 각 앱을 **git submodule(포크)** 로 둔다. 커밋 순서: 서브모듈 내부 commit/push → 부모에서 `git add <submodule>` 로 포인터 갱신 → push 가 `deploy.yml` 트리거.

### 애플리케이션 컴포넌트

| 컴포넌트 | 기술 | 포트 | 서빙 경로 |
|----------|------|------|-----------|
| client-web | React (Vite 정적 빌드) | — | `siseon.live` → CloudFront → S3 |
| admin-web | React (Vite 정적 빌드) | — | `app.siseon.live` → CloudFront → S3 |
| api-server | Spring Boot 3.2 / Java 21 | 8080 | `api.siseon.live` → GA → ALB (`/api/*`, `/ws/*`) |
| ai-module | FastAPI | 8000 | `api.siseon.live` → GA → ALB (`/ai/*`) |
| sensimul | Go 1.23+ | — | 온프레미스 IoT 시뮬레이터 |

> client-web / admin-web 은 더 이상 nginx 컨테이너로 EKS 에 뜨지 않는다. **정적 자산만 S3 에 올리고 CloudFront 가 서빙**한다.

---

## 아키텍처 — 공존 구조 (정적/동적 분리)

```
        [한국 사용자]                         [미국 사용자]
             │                                     │
   ┌─────────┴──────────┐              ┌───────────┴─────────┐
   │정적                 │동적          │동적                  │정적
   ▼                    ▼              ▼                     ▼
 siseon.live /           api.siseon.live                   (동일)
 app.siseon.live                │
   │                            ▼
   ▼                   Global Accelerator
 CloudFront   (지연 라우팅 + 페일오버, 진짜 클라이언트 IP 인식)
 (OAC, 엣지캐시)          │        │
   │             ┌───────┘        └────────┐
   ▼             ▼                          ▼
  S3         서울 ALB                   오하이오 ALB
(정적자산)    (HTTPS 443)               (HTTPS 443)
           /api /ws → spring          /api /ws → spring
           /ai      → fastapi         /ai      → fastapi
           default  → 404(fixed)      default  → 404(fixed)
                │                          │
            서울 EKS                   오하이오 EKS
         (api / ai / redis)          (api / ai / redis)
                │                          │
         서울 RDS (Master) ──────────→ 오하이오 RDS (Read Replica)
         읽기/쓰기                      읽기 / 쓰기는 서울로
```

- **정적(`siseon.live`, `app.siseon.live`)**: CloudFront → S3(OAC). API behavior 없음(순수 정적). SPA 라우팅은 403/404 → `index.html` 폴백.
- **동적(`api.siseon.live`)**: CloudFront 를 거치지 않고 GA 로만 흐른다 → GA 가 진짜 클라이언트 IP 를 인식 → 한국=서울 / 미국=오하이오 지연 라우팅 유지.
- 평상시: 한국 → 서울, 미국 → 오하이오 / 서울 장애 시: 한국 트래픽도 오하이오로 페일오버 + 오하이오 RDS Promote.

---

## 인프라 디렉토리 구조

```
Stockops-Infra/
├── modules/          # 공통 모듈 (vpc, alb, eks, db, ecr, github-oidc, iot, karpenter)
├── seoul/            # 서울 리전 (본사, 풀스택) + Route53 호스팅 존 + 서울 ACM(ALB용)
├── ohio/             # 오하이오 리전 (미국, 풀스택 미러) + 오하이오 ACM
└── global/           # Global Accelerator + Route53 A 레코드 + CloudFront/S3(OAC) + CloudFront ACM(us-east-1)
```

### Terraform State 구조 (S3 backend)

```
siseon-terraform-state/
└── infra/
    ├── seoul/terraform.tfstate     # Route53 호스팅 존 소유
    ├── ohio/terraform.tfstate
    └── global/terraform.tfstate
```

### DNS / 인증서 관리 구조

```
seoul/dns.tf   → Route53 호스팅 존 + 서울 ACM (ap-northeast-2, ALB HTTPS용)
ohio/dns.tf    → 오하이오 ACM (us-east-2, ALB HTTPS용)
global/acm.tf  → CloudFront ACM (us-east-1, siseon.live + *.siseon.live) ※ CloudFront는 us-east-1 인증서만 허용
global/dns.tf  → Route53 A 레코드:
                   siseon.live      → CloudFront(client)
                   app.siseon.live  → CloudFront(admin)
                   api.siseon.live  → Global Accelerator
```

> Route53 호스팅 존은 서울(본사) state 가 소유. 오하이오/글로벌은 `terraform_remote_state` 로 zone_id 참조.
> 도메인 NS 는 등록기관(가비아)에서 Route53 위임 세트로 교체.

---

## 배포된 AWS 리소스

| 리소스 | 서울 | 오하이오 | 글로벌 |
|--------|------|----------|--------|
| VPC | 10.0.0.0/16 | 10.1.0.0/16 | — |
| EKS | seoul-cluster v1.30 | ohio-cluster v1.30 | — |
| 노드 오토스케일 | Karpenter (replica 2) + HPA | Karpenter (replica 1) + HPA | — |
| ALB | HTTPS + 경로 라우팅 (api/ws/ai) | 동일 | — |
| RDS | PostgreSQL 16 (Master) | Read Replica | — |
| ECR | 2개 리포 (api, ai) | replication 자동 복제 | — |
| ACM | siseon.live (ALB, ap-northeast-2) | siseon.live (ALB, us-east-2) | siseon.live + *.siseon.live (CloudFront, us-east-1) |
| IoT Core + SQS + Firehose | ✅ | (SQS/IRSA 준비됨, Rule failover용) | — |
| Secrets Manager + ESO | ✅ | ✅ | — |
| Route53 호스팅 존 | ✅ (소유) | — | A 레코드 |
| CloudFront + S3 (정적 프론트) | — | — | client / admin (OAC) |
| Global Accelerator | — | — | HTTP/HTTPS 리스너, 서울/오하이오 ALB 엔드포인트 |
| api-server SQS 컨슈머 IRSA | ✅ (`stockops-api-sqs-role` + `stockops-api-sa`) | ✅ (`stockops-api-sqs-role-ohio`) | — |

---

## ALB 라우팅 규칙 (서울/오하이오 공통)

| Priority | 조건 | 대상 |
|----------|------|------|
| 5 | `/ws`, `/ws/*` | api-server (WebSocket / STOMP) |
| 10 | `/api`, `/api/*` | api-server (spring_tg) |
| 20 | `/ai`, `/ai/*` | ai-module (fastapi_tg) |
| default | 나머지 | **fixed-response 404** |

> HTTP(80) → HTTPS(301) 리다이렉트.
> 정적 프론트(client/admin)가 CloudFront/S3 로 이전되면서 **frontend_tg / admin_tg 타깃 그룹과 admin 호스트 룰(p85)은 제거**됨. ALB 에 남는 타깃 그룹은 `spring_tg` / `fastapi_tg` 둘뿐.
> ⚠️ GA 는 ALB 엔드포인트의 헬스를 **ALB 타깃 그룹 상태**로 판정한다(엔드포인트 그룹의 health_check_path 는 ALB 엔드포인트엔 무시됨). 따라서 `spring_tg`·`fastapi_tg` 가 **모두 healthy** 해야 GA 가 해당 ALB 를 healthy 로 본다.

---

## CORS

```
STOCKOPS_CORS_ALLOWED_ORIGINS = "https://app.siseon.live,https://siseon.live"
```

> 이 env var **하나로 REST CORS + STOMP WebSocket 오리진이 동시에 제어**된다(`CorsConfig` + `WebSocketConfig` 가 같은 프로퍼티 참조). OS env var 가 `application.yml`/프로파일보다 우선순위가 높다.
> refresh 쿠키: `HttpOnly` + `Secure` + `SameSite=Strict`, Path `/api/v1/auth`. `app/api.siseon.live` 는 eTLD+1 이 같아 same-site → Strict 로도 정상 전송.

---

## IoT 센서 파이프라인 (팬아웃)

```
온프레미스 센서 (sensormqtt.ithans.com)
    └─ Mosquitto 브리지 (TLS:8883)
         └─ AWS IoT Core (sensimul/sites/+/sensors/+)
              └─ IoT Rule ─┬─→ SQS (실시간: api-server 소비 → Redis 캐시 → 웹 표시 / WebSocket 푸시)
                           └─→ Kinesis Firehose → S3 (Hive 파티션, Parquet → Athena 분석)
```

- IoT Thing: `mosquitto-bridge` / 서울 엔드포인트: `a2ie1b3xp2emgi-ats.iot.ap-northeast-2.amazonaws.com`
- 현장/센서: `TEST_INDOOR_01`(테스트) 외에 운영 센터 `CT-SEL / CT-ICN / CT-PUS / CT-DAE / CT-GWJ` 의 DOOR/온습도/공기질 센서가 실시간 발행 중
- 센서 메시지 포맷: snake_case JSON (`site_id`, `sensor_id`, `sensor_type`, `value` ...)

> destroy/재apply 시 IoT 인증서 새로 발급 → 온프레미스 브리지 재설정 필요.

### ✅ SQS 컨슈머 → 실시간 표시 경로 (2026-06-15 E2E 완성)

`api-server` 가 SQS 큐(`stockops-sensor-data`)를 폴링해 센서 텔레메트리를 소비하고, `sensor_devices` 등록 정보와 매칭한 뒤 Redis 캐시에 적재 → 웹이 `/sensors/{id}/readings/recent` 로 조회하는 경로를 끝까지 검증했다. 동작에 필요했던 5개 선결 조건:

| # | 구분 | 항목 | 조치 |
|---|------|------|------|
| 1 | 인프라 (env) | SQS ingestion 미활성 | `STOCKOPS_SQS_INGESTION_ENABLED=true` + `STOCKOPS_SQS_INGESTION_QUEUE_URL` + `STOCKOPS_SQS_INGESTION_REGION` 주입 (seoul/kubernetes.tf) |
| 2 | 인프라 (IRSA) | api-server 파드에 SQS 읽기 권한 없음 | `stockops-api-sqs-role`(IRSA) + `stockops-api-sa` SA 생성·연결, `sqs:ReceiveMessage/DeleteMessage/...` 부여 (seoul/iot.tf) |
| 3 | 앱 (pom.xml) | AWS SDK `sts` 모듈 누락 → IRSA 토큰 발급 실패(`Unexpected SQS ingestion failure`) | `software.amazon.awssdk:sts` 의존성 추가 |
| 4 | 앱 (코드) | 센서 JSON(snake_case) ↔ DTO(camelCase) 필드명 불일치로 `siteId/sensorId` 가 null → `Skipping malformed` | `SensimulPayload` 6개 필드에 `@JsonProperty("site_id")` 등 매핑 추가 |
| 5 | DB (시드) | `sensor_devices` 미등록 → `findByMqttTopic` 매칭 실패로 전량 drop | DOOR 센서 20개(5센터 × 4) + 온도 센서 1개(`CT-SEL-FRZ-T01`) 등록 |

> mqtt_topic 매칭 규칙: `sensimul/sites/{site_id}/sensors/{sensor_id}`. `sensor_devices.mqtt_topic` 와 정확히 일치해야 ingest 된다.
> 등록 안 된 토픽은 `Skipping telemetry for unknown or deleted sensor topic` 로그를 남기고 버려진다(에러 아님).
> 검증: SQS 큐 backlog 136k → 14건으로 정상 소비 확인, Redis `stockops:sensor:readings:1~20` 키 생성 확인.

---

## 시크릿 관리 (ESO)

```
Secrets Manager (stockops/app)
    └─ ClusterSecretStore (v1)
         └─ ExternalSecret (1h 주기 동기화)
              └─ K8s Secret (stockops-secret) 자동 생성
                   └─ 파드 환경변수 주입 (DB/JWT 등)
```

> destroy/재apply 후 `stockops-secret` 수동 생성 불필요(ESO 자동 복구). apply 직후 `kubectl get secret stockops-secret -n stockops` 로 동기화 확인(없으면 api-server CrashLoopBackOff).

> ⚠️ **보안 점검 항목(예정)**: 현재 `jwt_secret`/`db_password` 는 로컬 `terraform.tfvars` 평문 입력 → state(S3)에도 평문 저장된다. (1) `*.tfvars` `.gitignore` 확인, (2) 변수에 `sensitive = true`, (3) state 버킷 SSE + IAM 접근 제어, (4) 장기적으로 Secrets Manager data source 조회 / `random_password` / `ignore_changes` 패턴으로 전환 검토.

---

## 팀 클러스터 접근 (aws-auth)

- 팀원 4명은 IAM Identity Center(SSO) 권한셋 `AWSReservedSSO_AdministratorAccess` 사용.
- `seoul/kubernetes.tf` 의 `aws-auth` ConfigMap `mapRoles` 에 해당 권한셋 role ARN 1건 매핑(`{{SessionName}}` 으로 4명 공통 커버) → kubectl/ArgoCD 작업 가능.

```hcl
{
  rolearn  = "arn:aws:iam::448768137813:role/aws-reserved/sso.amazonaws.com/ap-northeast-2/AWSReservedSSO_AdministratorAccess_<hash>"
  username = "sso-user:{{SessionName}}"
  groups   = ["system:masters"]
}
```

### ArgoCD 접근 (CD 작업용)

ArgoCD 는 `ClusterIP` 로 떠 있어 외부 URL 이 없다. 포트포워딩으로 접근:

```powershell
kubectl port-forward svc/argocd-server -n argocd 8080:443
# https://localhost:8080 / admin / (아래 초기 비밀번호)
$b64 = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))
```

---

## CI/CD

```
GitHub Actions (CI) — main push / workflow_dispatch
├─ [정적] client-web / admin-web
│    └─ Vite 빌드 (.env.production: VITE_API_BASE_URL=https://api.siseon.live/api)
│         └─ aws s3 sync --delete  →  CloudFront create-invalidation
│
└─ [동적] api-server / ai-module
     └─ 이미지 빌드  →  서울 ECR push (OIDC, 액세스 키 없음)
          └─ 서울 ECR → 오하이오 ECR 자동 replication (CRR)
               └─ kubectl rollout restart (EKS 재배포; 서울 자동 + 오하이오 스텝)

ArgoCD (CD) — v7.7.0 설치 완료, 앱 구성 예정 (허브-스포크: 서울 ArgoCD 가 서울+오하이오 관리)
```

> GitHub Actions Role(OIDC, `github-actions-ecr-push`)은 각 EKS `aws-auth` ConfigMap 에 등록되어 있어야 `kubectl rollout restart` 가 동작(Terraform 관리). 오하이오 롤아웃을 쓰려면 오하이오 `aws-auth` 에도 동일 롤 매핑 필요.
> CRR 비동기 race(롤아웃이 복제보다 빠른 경우) 대응: 오하이오에서 `kubectl rollout restart deployment/stockops-api -n stockops` 로 수동 재롤아웃.

---

## 배포 방법

### 사전 준비
- AWS SSO 로그인 (`aws sso login --profile siseon`)
- kubectl, terraform 설치
- 각 리전 `terraform.tfvars` 생성 (jwt_secret, db_username, db_password)
- 정적 프론트 S3 버킷(`siseon-frontend-client`, `siseon-frontend-admin`)은 사전 존재(글로벌이 `data` 로 참조)

### 배포 순서 (`seoul → ohio → global`)

```powershell
# 1. 서울
cd seoul
aws eks update-kubeconfig --region ap-northeast-2 --name seoul-cluster --profile siseon
terraform apply -auto-approve

# 2. 오하이오 (※ 현재는 비용 절감차 생략 가능 — global의 ohio 참조를 off로 둔 경우)
cd ..\ohio
terraform apply --% -auto-approve -target=aws_acm_certificate.ohio -target=aws_route53_record.cert_validation -target=aws_acm_certificate_validation.ohio
terraform apply --% -auto-approve -target=module.ohio_vpc -target=module.ohio_alb -target=module.ohio_eks -target=aws_db_instance.ohio_replica
aws eks update-kubeconfig --region us-east-2 --name ohio-cluster --profile siseon
terraform apply -auto-approve

# 3. 글로벌 (GA + Route53 A + CloudFront/S3 + CloudFront ACM)
cd ..\global
terraform apply -auto-approve
```

> 오하이오를 올리지 않을 때는 `global` 의 `terraform_remote_state.ohio` + 오하이오 GA 엔드포인트 그룹을 off(주석 또는 `enable_ohio=false`)로 두고 `seoul → global` 만 apply.
> Cross-Region Replica(오하이오 RDS) 생성에 약 25분. ACM 검증은 NS 전파 후 자동 완료(5~15분).

### 센서 디바이스 등록 (실시간 표시 전제)

api-server 가 SQS 데이터를 받아도 `sensor_devices` 에 등록된 토픽만 화면에 표시된다. RDS 에 직접 INSERT(또는 admin-web/`SensorDeviceController`):

```sql
INSERT INTO sensor_devices (
    name, location, sensor_type, external_sensor_id, mqtt_topic,
    unit, calibration, noise_sigma, warn_min, warn_max, crit_min, crit_max, deleted, active
) VALUES (...);
-- mqtt_topic = 'sensimul/sites/{site_id}/sensors/{sensor_id}' 형식 필수
```

> 로컬에 psql 미설치 시 임시 파드 사용:
> `kubectl run psql-temp -n stockops --rm -it --restart=Never --image=postgres:16-alpine -- sh`
> 등록 후 로그에 `Skipping telemetry ... unknown sensor topic` 이 해당 토픽에 대해 사라지면 정상.

### 애플리케이션 배포 (GitHub Actions)
```
<pull>
cd C:\KJW\combined-repo
git submodule update --remote --merge
git add .
git commit -m "Sync submodules to latest"
git push

<push>
cd C:\KJW\combined-repo\sensimul
git add .
git commit -m "feat: 뭔가 수정"
git push origin main

cd C:\KJW\combined-repo
git add sensimul
git commit -m "Update sensimul submodule pointer"
git push origin main
```

```powershell
gh workflow run deploy.yml
```

- 정적(client/admin): Vite 빌드 → S3 sync → CloudFront 무효화
- 동적(api/ai): 이미지 빌드 → 서울 ECR push(OIDC) → CRR → `kubectl rollout restart`

### 검증

```powershell
kubectl get pods -n stockops
terraform -chdir=global output

# 동적 API + CORS
curl.exe -i -X OPTIONS https://api.siseon.live/api/v1/auth/login -H "Origin: https://app.siseon.live" -H "Access-Control-Request-Method: POST" | findstr /I "HTTP Access-Control-Allow"

# 타깃 그룹 헬스 (GA 健康의 전제 — 둘 다 healthy 여야 함)
foreach ($n in "seoul-spring-tg","seoul-fastapi-tg") {
  $tg = aws elbv2 describe-target-groups --names $n --region ap-northeast-2 --profile siseon --query "TargetGroups[0].TargetGroupArn" --output text
  aws elbv2 describe-target-health --target-group-arn $tg --region ap-northeast-2 --profile siseon --query "TargetHealthDescriptions[].TargetHealth.State" --output text
}

# 센서 SQS 소비 검증
aws sqs get-queue-attributes --queue-url $Q --attribute-names ApproximateNumberOfMessages --profile siseon --region ap-northeast-2
kubectl exec -it -n stockops deploy/stockops-redis -- redis-cli KEYS "stockops:sensor:readings:*"
kubectl logs -n stockops -l app=stockops-api --tail=100 | findstr /I "SQS ingestion started Skipping"
```

### 초기 로그인 계정
- 이메일: `admin@stockops.com`
- 비밀번호: `admin123`

---

## 종료 (destroy)

**반드시 역순으로 진행 (`global → ohio → seoul`)**

```powershell
# 1. 글로벌 (GA가 ALB 참조 → 먼저 삭제)
cd global
terraform destroy -auto-approve

# 2. 오하이오 (TGB 먼저)
cd ..\ohio
terraform destroy --% -auto-approve -target=kubectl_manifest.api_tgb -target=kubectl_manifest.ai_tgb
terraform destroy -auto-approve

# 3. 서울 (ArgoCD CRD + TGB 먼저)
cd ..\seoul
kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io --ignore-not-found
terraform destroy --% -auto-approve -target=kubectl_manifest.api_tgb -target=kubectl_manifest.ai_tgb
terraform destroy -auto-approve
```

> 프론트가 CloudFront/S3 로 이전된 뒤로 TGB 는 `api_tgb`/`ai_tgb` 만 존재(client_tgb/admin_tgb 제거됨).
> 정적 S3 버킷은 `data` 참조라 destroy 해도 버킷·자산 유지(팀 패턴).
> destroy 순서 위반 시 Cross-Region ACM 참조 에러 발생. 오하이오 RDS(Replica)는 서울 RDS보다 먼저 삭제.
> IoT Policy/Thing detach 실패(외부 참조 인증서가 state에 없을 때) 시 수동 `aws iot detach-policy` / `aws iot detach-thing-principal` 필요.

### destroy 후 잔재 확인

```powershell
aws ec2 describe-vpcs --region ap-northeast-2 --profile siseon --query "Vpcs[?IsDefault=='false'].VpcId"
aws ec2 describe-vpcs --region us-east-2 --profile siseon --query "Vpcs[?IsDefault=='false'].VpcId"
aws eks list-clusters --region ap-northeast-2 --profile siseon
aws eks list-clusters --region us-east-2 --profile siseon
aws globalaccelerator list-accelerators --region us-west-2 --profile siseon --query "Accelerators[*].Name"
```

---

## IoT 인증서 추출 (현수님 전달용)

```powershell
# destroy/재apply 후 실행
$cert = terraform output -json certificate_pem | ConvertFrom-Json
[System.IO.File]::WriteAllText("$PWD\mosquitto-bridge.cert.pem", $cert)

$key = terraform output -json private_key | ConvertFrom-Json
[System.IO.File]::WriteAllText("$PWD\mosquitto-bridge.private.key", $key)

# AmazonRootCA1.pem (고정값 — 전 리전 공통, 서울/오하이오 동일 파일 재사용 가능)
Invoke-WebRequest -Uri "https://www.amazontrust.com/repository/AmazonRootCA1.pem" -OutFile "AmazonRootCA1.pem"
```

> 오하이오 브리지 접속 4종: `AmazonRootCA1.pem`(서울 것 재사용) + `ohio-device.cert.pem` + `ohio-device.private.key` + 오하이오 엔드포인트(`a2ie1b3xp2emgi-ats.iot.us-east-2.amazonaws.com`). `*.public.key` 는 접속에 사용 안 함.

---

## 로드맵

- [x] VPC + EKS + ALB + RDS + ECR 배포 (서울)
- [x] GitHub Actions OIDC 전환 (액세스 키 제거)
- [x] IoT Core + SQS + Firehose 팬아웃 파이프라인 (실시간 + Parquet/Athena 분석)
- [x] S3 Terraform backend + state 중앙화 (seoul/ohio/global 분리)
- [x] Secrets Manager + ESO 연동 (시크릿 자동화)
- [x] ArgoCD 설치
- [x] 멀티 리전 (오하이오) 풀스택 + ECR replication
- [x] Cross-Region RDS Read Replica
- [x] Global Accelerator (HTTP/HTTPS 리스너, 지연 라우팅)
- [x] Karpenter + HPA (노드/파드 오토스케일링)
- [x] 팀 도메인 연결 (**siseon.live**) + Route53 위임 세트
- [x] ACM HTTPS (ALB + CloudFront 인증서 분리)
- [x] CORS 환경변수 적용 (`STOCKOPS_CORS_ALLOWED_ORIGINS` — REST+WS 동시 제어)
- [x] WebSocket ALB 룰 (`/ws`)
- [x] **정적 프론트 CloudFront + S3(OAC) 전환** (client/admin nginx EKS 제거, ALB 타깃그룹 정리)
- [x] IoT 브리지 연결 확인
- [x] 멀티리전 ECR 직접 push(Option B) + 이미지 SHA 태그 (CRR race 제거, 리전별 롤백)
- [x] 서울 RDS Multi-AZ 활성화 (지금은 주석)
- [x] WAF — ALB/GA/CloudFront 앞단 보안
- [x] **api-server SQS 컨슈머 → Redis → 웹 실시간 표시 E2E 완성** (env+IRSA+sts+JSON매핑+센서등록) ✨ 2026-06-15
- [x] **팀원 SSO 권한셋 aws-auth 매핑** (kubectl/ArgoCD 공동 작업)
- [ ] AI 기능 활성화 (Bedrock/Gemini/Vertex 중 택1 — 제공자 기본 비활성, Model Access + IRSA/키 필요. 비용 절감 위해 별도 프리티어 계정 크로스어카운트 검토 중)
- [ ] 나머지 센서(온습도/공기질) 등록 + 임계치(warn/crit) 설정 → 알림 로직 연동
- [ ] 오하이오 SQS 컨슈머 검증 (failover 시 동일 경로) + 오하이오 sensor_devices 등록
- [ ] 시크릿 평문 입력 개선 (tfvars → Secrets Manager data source / random_password)
- [ ] ArgoCD 앱 구성 (GitOps CD)
- [ ] Azure 트랜잭션 로그 백업 (3차 방어)
- [ ] Observability 스택 (Grafana/Prometheus)

자세한 아키텍처는 `ARCHITECTURE.md`, AWS 리소스 목록은 `AWS_RESOURCES.md` 참고.