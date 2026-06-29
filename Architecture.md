# StockOps — 멀티 하이브리드 클라우드 인프라 아키텍처

> **팀명**: 시선 (SysSun — System Surveillance & Unified Network)
> **프로젝트 주제**: AX 환경을 위한 ERP 솔루션 기반 멀티 하이브리드 클라우드 인프라 자동화 및 Observability 체계 구축
> **애플리케이션**: StockOps
> **도메인**: `siseon.live`

---

## 1. 프로젝트 개요

StockOps는 AX(AI Transformation) 환경의 ERP/WMS 솔루션으로, 멀티 리전·하이브리드 클라우드 위에서 동작한다. 인프라 자동화(IaC)와 장애 내결함성 확보를 핵심 목표로 한다.

비즈니스 맥락은 K-Food(예: 비비고 만두)의 해외 수요 증가다. 서울 본사가 운영을 총괄하고, 미국 영업팀이 현지 영업을 지원한다. 영업팀은 본사 운영에 지장을 주지 않도록 최소 권한으로 애플리케이션과 DB에 접근한다.

핵심 설계는 **공존(coexistence) 구조** — 정적 프론트(client/admin)는 CloudFront + S3(OAC)로 서빙하고, 동적 API/WS/AI 는 Global Accelerator → ALB → EKS 로 흐른다. 두 트래픽을 도메인 단위로 분리하여 정적은 엣지 캐시 이점을, 동적은 GA 의 진짜 클라이언트 IP 기반 멀티리전 라우팅을 각각 살린다.

---

## 2. 인프라 분포

| 위치 | 역할 |
|------|------|
| AWS 서울 리전 (ap-northeast-2) | 본사. 한국 사용자 메인 서비스 (풀스택) |
| AWS 오하이오 리전 (us-east-2) | 미국 영업팀 서비스 (풀스택 미러, 페일오버) |
| 온프레미스 (한국) | 센터/창고. 센서 데이터 수집 |
| Azure (재해 복구) | RDS 백업 저장 (3차 방어 — DR 파이프라인) |

---

## 3. 데이터 전략 (3단계 방어)

```
1차 방어 — Multi-AZ (서울 내 AZ 장애)
    서울 RDS Primary ↔ Standby 자동 전환 (다운타임 1~2분)
    ※ 비용 절감차 코드상 multi_az 주석 처리 — 실배포 직전 활성화

2차 방어 — Cross-Region Replica (서울 리전 전체 장애)
    서울 RDS (Master) → 오하이오 RDS (Read Replica) 실시간 복제
    리전 장애 시 오하이오 Promote → Master 승격

3차 방어 — Azure 백업 (AWS 전체 마비)  ※ 시온님 DR 설계 기반
    EventBridge(주 1회) → DR 백업 태스크(pg_dump | gzip) → S3 → Azure Blob
    AWS 전체 장애 시 Azure에서 복구
```

### 평상시 DB 흐름

```
서울 api    → 읽기/쓰기 → 서울 RDS (Master)
오하이오 api → 읽기      → 오하이오 RDS (Read Replica)
            → 쓰기      → 서울 RDS (Master, 리전 간 경유 ~150ms)
```

미국 영업팀의 발주 등 쓰기는 서울 Master에 저장되어 본사에서도 확인 가능. 읽기는 가까운 오하이오 Replica로 처리하여 지연 최소화.

### RTO / RPO

| 방어 단계 | 장애 범위 | RTO | RPO |
|-----------|-----------|-----|-----|
| 1차 Multi-AZ | AZ 단위 | 1~2분 (자동) | 0 (동기) |
| 2차 Cross-Region | 리전 단위 | 수 분 (수동 Promote) | 수 초~수 분 |
| 3차 Azure 백업 | AWS 전체 | 수 시간 (수동) | 최대 백업 주기 |

> Promote 자동화(RDS Event → SNS → Lambda)는 추후 과제. 현재는 수동.

### DR 백업 파이프라인 (`seoul/dr.tf` — 시온님 설계)

```
EventBridge Rule (cron(0 17 ? * SUN), 주 1회)
    └─ DR 백업 태스크 (ECR 이미지: stockops-dr-ecr)
         └─ pg_dump (PostgreSQL 18) | gzip
              └─ S3 (stockops-rds-backup-<account>)  ─→  Azure Blob (rds-to-azure)
```

- 컨테이너 이미지 `rds-to-azure`(Amazon Linux 2023 + PostgreSQL 18 client + azure-storage-blob)는 빌드/푸시 완료, ECR(`stockops-dr-ecr`)에서 `data` 소스로 참조.
- 현재 Terraform 으로 프로비저닝된 것: DR 전용 SG(`seoul-dr-backup-sg`) + DB SG 인바운드 허용 + IAM 롤 2종(`seoul-dr-backup-task-role` 쓰기 / `seoul-dr-reader-role` 읽기) + EventBridge 규칙 + S3/ECR `data` 참조.
- **Lambda 함수 본체와 EventBridge 타깃 연결은 주석 처리(배포 대기)** — 인프라 토대만 먼저 깔아둔 상태.

---

## 4. 트래픽 / 라우팅 전략 (공존 구조)

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
 CloudFront   (지연 라우팅 + 페일오버, 진짜 클라이언트 IP 보존)
 (OAC, 엣지캐시)          │        │
   │             ┌───────┘        └────────┐
   ▼             ▼                          ▼
  S3         서울 ALB                   오하이오 ALB
(정적자산)    (HTTPS 443)               (HTTPS 443)
           /ws /api /ai → EKS          /ws /api /ai → EKS
           default → 404(fixed)        default → 404(fixed)
```

- **정적(`siseon.live`, `app.siseon.live`)**: Route53 A(Alias) → CloudFront → S3(OAC). API behavior 없음(순수 정적). SPA 라우팅은 403/404 → `index.html` 폴백.
- **동적(`api.siseon.live`)**: Route53 A(Alias) → Global Accelerator → 가까운 리전 ALB. CloudFront 를 거치지 않으므로 GA 가 진짜 클라이언트 IP 를 인식 → 한국=서울 / 미국=오하이오 지연 라우팅 유지.
- GA 는 **리전 라우팅 + 페일오버**, ALB 는 **서비스 분기(경로 기반)** 를 담당 — 역할 분리.

### Global Accelerator

- 관리 리전: us-west-2 (GA 글로벌 리소스)
- 리스너: **TCP 80 + TCP 443** (2개)
- 엔드포인트 그룹: **현재 서울(ap-northeast-2) only** (HTTP/HTTPS), `traffic_dial 100%`, `client_ip_preservation_enabled = true`
- 헬스체크: HTTP/HTTPS `/`, 30초 간격, threshold 3

> ⚠️ GA 는 ALB 엔드포인트의 헬스를 **ALB 타깃 그룹 상태**로 판정한다. `spring_tg`·`fastapi_tg` 가 모두 healthy 해야 GA 가 해당 ALB 를 healthy 로 본다(엔드포인트 그룹의 `health_check_path` 는 ALB 엔드포인트에 무시됨).
> **오하이오 엔드포인트 그룹(`ohio_http`/`ohio_https`) 및 `terraform_remote_state.ohio`는 현재 주석 처리** — Ohio 미배포 상태. Ohio 재배포 후 주석 해제 필요.

---

## 5. 온프레미스 연동 (센서 데이터 파이프라인 — 팬아웃)

```
[온프레미스 창고 센서 — sensormqtt.ithans.com]
        │ Mosquitto 브리지 (TLS:8883)
        ▼
   [AWS IoT Core — 서울]
   Topic: sensimul/sites/+/sensors/+
   IoT Rule SQL: SELECT *, topic() as mqtt_topic FROM 'sensimul/sites/+/sensors/+'
        │
        ├─→ [SQS: stockops-sensor-data]  (실시간)
        │        └─ api-server(IRSA) consume → Redis 캐시 → 웹 표시 / WebSocket 푸시
        │        └─ 실패 시 [DLQ: stockops-sensor-data-dlq] (14일 보관)
        │
        └─→ [Kinesis Firehose: stockops-sensor-history]  (이력)
                 └─ S3 (stockops-sensor-data)
                      GZIP, 15분/5MB 버퍼, 날짜 파티션(year/month/day) → Athena 분석
```

- IoT Thing: `mosquitto-bridge` / 서울 엔드포인트: `a2ie1b3xp2emgi-ats.iot.ap-northeast-2.amazonaws.com`
- IoT 정책: `iot:Connect`(client/mosquitto-bridge-seoul) + `iot:Publish`(topic/sensimul/sites/*)
- 인증서는 `var.iot_certificate_arn` 로 **외부 참조**(콘솔 발급) → destroy/재apply 사이클에서도 인증서 유지(브리지 재설정 불필요).
- 센서 메시지 포맷: snake_case JSON (`site_id`, `sensor_id`, `sensor_type`, `value` ...). `mqtt_topic` 은 IoT Rule 이 `topic()` 으로 주입.

> IoT 는 서울에만 구성(센서가 한국 온프레미스에 위치). 오하이오는 페일오버용 SQS 경로만 별도 구성(Firehose 없음, IoT Rule 도 SQS only).
> SQS 컨슈머 → Redis → 웹 실시간 표시 경로는 E2E 검증 완료(env + IRSA + AWS SDK sts + snake_case↔DTO 매핑 + sensor_devices 등록).

---

## 6. 애플리케이션 구성 (Stockops-Application — 모노레포)

https://github.com/jinuuuKim/Stockops-Application

| 컴포넌트 | 설명 | 포트 | 서빙 경로 |
|----------|------|------|-----------|
| `client-web` | 사용자 포털 (React / Vite 정적 빌드) | — | `siseon.live` → CloudFront → S3 |
| `admin-web` | 관리자 웹 (React / Vite 정적 빌드) | — | `app.siseon.live` → CloudFront → S3 |
| `api-server` | 메인 백엔드 (Spring Boot 3.2, Java 21) | 8080 | `api.siseon.live` → GA → ALB (`/api/*`, `/ws/*`) |
| `ai-module` | AI 수요 예측 (FastAPI) | 8000 | `api.siseon.live` → GA → ALB (`/ai/*`) |
| `sensimul` | 온프레미스 IoT 시뮬레이터 (Go) | — | 온프레미스 |

> client-web / admin-web 은 더 이상 nginx 컨테이너로 EKS 에 뜨지 않는다. **정적 자산만 S3 에 올리고 CloudFront 가 서빙**한다(ALB 타깃 그룹/EKS 파드 제거됨).

### CI/CD

```
GitHub Actions (CI) — main push / workflow_dispatch
├─ [정적] client-web / admin-web
│    └─ Vite 빌드 → aws s3 sync --delete → CloudFront 무효화
└─ [동적] api-server / ai-module
     └─ 이미지 빌드 → 서울 ECR + 오하이오 ECR 각각 직접 push (OIDC, Option B)
          └─ kubectl rollout restart

ArgoCD (CD) — v7.7.0 설치 완료, 앱 구성 예정 (허브-스포크: 서울 ArgoCD 가 서울+오하이오 관리)
```

- OIDC 인증(`github-actions-ecr-push`): `role-to-assume` 방식, 액세스 키 없음. `ecr_arns` 에 서울+오하이오 리포 ARN 모두 포함.
- **ECR 은 리전별 독립 리포**(서울/오하이오 각각 `stockops-api`/`stockops-ai`)이며 CI 가 양 리전에 직접 push(Option B). CRR(Cross-Region Replication) 미사용 → 복제 지연 race 없음, 리전별 롤백 가능.
- Terraform 이 ECR(그릇)을 만들고, GitHub Actions 가 이미지(내용물)를 채운다.

### CORS

```
STOCKOPS_CORS_ALLOWED_ORIGINS = "https://app.siseon.live,https://siseon.live"
```

> 이 env var **하나로 REST CORS + STOMP WebSocket 오리진이 동시에 제어**된다(`CorsConfig` + `WebSocketConfig` 가 같은 프로퍼티 참조). OS env var 가 `application.yml`/프로파일보다 우선.
> refresh 쿠키: `HttpOnly` + `Secure` + `SameSite=Strict`, Path `/api/v1/auth`. `app/api.siseon.live` 는 eTLD+1 이 같아 same-site → Strict 로도 정상 전송.

### 주요 설정 노트
- 필수 환경변수: `JWT_SECRET`, `STOCKOPS_DATASOURCE_URL/USERNAME/PASSWORD`, `SPRING_DATA_REDIS_HOST`, `STOCKOPS_CORS_ALLOWED_ORIGINS`, `STOCKOPS_SQS_INGESTION_*`
- 헬스체크: Spring `/actuator/health` (Redis 필수), FastAPI `/health`
- API prefix: `/api/v1/...`
- 초기 admin: `admin@stockops.com` / `admin123`

---

## 7. 인프라 구성 (Stockops-Infra — Terraform)

### 디렉토리 구조
```
Stockops-Infra/
├── bootstrap/        # state 버킷 하드닝 + KMS(siseon-tfstate) — 로컬 백엔드
├── modules/          # 공통 모듈
│   ├── alb/          # ALB (idle_timeout=120s) + Target Groups + HTTPS + REGIONAL WAF
│   ├── db/           # RDS PostgreSQL 18 + 파라미터 그룹
│   ├── ecr/          # ECR 리포 (for_each, KMS, lifecycle)
│   ├── eks/          # EKS + 관리형 노드그룹 + IRSA(LBC) + OIDC
│   ├── github-oidc/  # GitHub Actions OIDC Provider + IAM Role
│   ├── iot/          # IoT Thing + Rule + SQS/DLQ + Firehose→S3
│   ├── karpenter/    # Karpenter + NodePool/EC2NodeClass + 인터럽션 SQS
│   └── vpc/          # VPC + 3-Tier Subnets (karpenter.sh/discovery 태그)
├── regions/
│   ├── seoul/        # 서울 (풀스택 + IoT + DR + Route53 존 + 서울 ACM + GitHub OIDC)
│   ├── ohio/         # 오하이오 (풀스택 미러 + RDS Read Replica + 오하이오 ACM + 페일오버 IoT)
│   └── global/       # Global Accelerator + Route53 A + CloudFront/S3(OAC) + CloudFront ACM/WAF
└── peering/          # Seoul ↔ Ohio VPC 피어링 (remote_state로 VPC ID·RT ID 참조, 하드코딩 없음)
```

### Terraform State (S3 backend)

```
siseon-terraform-state/
└── infra/
    ├── seoul/terraform.tfstate     # Route53 호스팅 존 + 커스텀 시크릿 소유
    ├── ohio/terraform.tfstate
    ├── peering/terraform.tfstate   # VPC Peering + 양방향 Route
    └── global/terraform.tfstate
```

- state at-rest 암호화 ON(`alias/siseon-tfstate` KMS) + S3 네이티브 락(`use_lockfile`, TF 1.10+) + 버저닝 + 퍼블릭 차단 + 비-TLS 거부 정책 (bootstrap 이 구성).
- `global`/`ohio` 는 `terraform_remote_state` 로 seoul 의 ALB ARN·zone_id·시크릿 ARN 을 동적 참조 → **순서 의존성** 발생.

### 네트워크

| 리전 | VPC CIDR | Public | Private App | Private DB |
|------|----------|--------|-------------|------------|
| 서울 | 10.0.0.0/16 | 10.0.1~2.0/24 | 10.0.11~12.0/24 | 10.0.21~22.0/24 |
| 오하이오 | 10.1.0.0/16 | 10.1.1~2.0/24 | 10.1.11~12.0/24 | 10.1.21~22.0/24 |

각 리전: IGW + NAT GW 1개 + 3계층 라우팅 테이블. Public/Private App 서브넷에 EKS·Karpenter discovery 태그(`kubernetes.io/role/*`, `karpenter.sh/discovery`).

### EKS + 오토스케일링

- 서울 `seoul-cluster` / 오하이오 `ohio-cluster` (둘 다 **v1.30**), endpoint private+public.
- **관리형 노드그룹**: t3.medium, min 2 / desired 2 / max 4 (기본 캐파).
- **Karpenter**(helm 1.3.3): Pending 파드 → EC2 동적 프로비저닝. `spot` + `on-demand`, `t3.medium`/`t3.large`, amd64, AMI `al2023@latest`. limits cpu 8 / mem 16Gi, consolidation `WhenEmptyOrUnderutilized`(1m). Spot 인터럽션 핸들링용 SQS 큐 별도.
- **HPA**: `stockops-api`(CPU 60%, min 1 / max 4), `stockops-ai`(CPU 60% + Memory 70%, min 1 / max 4) — metrics-server 필요.
- AWS Load Balancer Controller(IRSA + OIDC) — helm_release.
- TargetGroupBinding(`targetType: ip`, immutable)으로 ALB ↔ Pod 연결. `kubectl_manifest`(gavinbunney/kubectl)로 plan-time 검증 회피, `depends_on = LBC`.
- Redis 는 클러스터 내 Pod(redis:7-alpine). **api/ai Deployment 는 Terraform 이 아니라 CI/ArgoCD 가 관리** — Terraform 은 Service/SA/HPA/TGB/Redis/ESO/aws-auth 만 소유.

### ALB 라우팅 (호스트 분리 + 경로 기반)

ALB 에는 정적 프론트가 없으므로 타깃 그룹은 `spring_tg`(8080) / `fastapi_tg`(8000) 둘뿐.

| Priority | 조건 | 대상 |
|----------|------|------|
| 5 | `/ws`, `/ws/*` | api-server (WebSocket / STOMP) |
| 10 | `/api`, `/api/*` | api-server (spring_tg) |
| 20 | `/ai`, `/ai/*` | ai-module (fastapi_tg) |
| default | 나머지 | **fixed-response 404** |

- HTTP(80) → HTTPS(443) 301 리다이렉트. HTTPS 리스너 SSL 정책 `ELBSecurityPolicy-TLS13-1-2-2021-06`.
- 헬스체크: Spring `/actuator/health`(8080), FastAPI `/health`(8000), 30s/threshold 3.

### WAF (2계층)

| Scope | 대상 | 룰 |
|-------|------|----|
| REGIONAL | 서울/오하이오 ALB | CommonRuleSet(관찰 count), KnownBadInputs(block), SQLi(관찰 count), LoginRateLimit(`/api/v1/auth/login` 100/5분 block), RateLimit(2000/5분 block) |
| CLOUDFRONT (us-east-1) | client/admin CloudFront | CommonRuleSet(관찰 count), AmazonIpReputationList(block) |

> 일부 매니지드 룰은 오탐 방지 위해 **관찰 모드(count)** 로 시작 → CloudWatch 메트릭/샘플 확인 후 block 전환. WAF 로그는 전용 CloudWatch 로그 그룹(7일 보관)에 적재.

### DNS / 인증서

```
seoul/dns.tf   → Route53 호스팅 존(소유, 위임셋 N02295603ILJ5HVTJBLTY) + 서울 ACM (ap-northeast-2, ALB HTTPS)
ohio/dns.tf    → 오하이오 ACM (us-east-2, ALB HTTPS) — 검증 레코드는 서울 존에 생성
global/acm.tf  → CloudFront ACM (us-east-1, siseon.live + *.siseon.live) ※ CloudFront 는 us-east-1 인증서만 허용
global/dns.tf  → Route53 A(Alias):
                   siseon.live      → CloudFront(client)
                   app.siseon.live  → CloudFront(admin)
                   api.siseon.live  → Global Accelerator
```

> 호스팅 존은 서울 state 가 소유. 오하이오/글로벌은 `terraform_remote_state` 로 `route53_zone_id` 참조하여 같은 존에 레코드 생성(`allow_overwrite`로 공존). 도메인 NS 는 등록기관(가비아)에서 Route53 위임 세트로 교체.

### 정적 프론트 (CloudFront + S3 + OAC)

- S3 버킷(`siseon-frontend-client` / `siseon-frontend-admin`)은 **사전 존재** → `data` 소스 참조(Terraform 이 생성/삭제 X, destroy 해도 버킷·자산 유지).
- 퍼블릭 접근 전면 차단(PAB) + OAC 전용 버킷 정책(해당 CloudFront 배포만 `s3:GetObject`).
- CloudFront: `PriceClass_200`(아시아+미국+유럽), `Managed-CachingOptimized`, SPA fallback(403/404 → `index.html`), TLSv1.2_2021, gzip 압축.

### 시크릿 관리 (ESO)

```
Secrets Manager (stockops/app)
    └─ ClusterSecretStore (external-secrets.io/v1) → ExternalSecret (1h)
         └─ K8s Secret (stockops-secret) 자동 생성 → 파드 주입
```

- 서울 ESO IRSA(`stockops-eso-role`) / 오하이오 ESO IRSA(`ohio-eso-role`)로 Secrets Manager 접근.
- 오하이오 ESO 는 `terraform_remote_state` 로 **서울 시크릿 ARN 을 cross-region 참조**(단일 시크릿 공유).
- 시크릿 키: `JWT_SECRET`, `DB_USERNAME/PASSWORD`, `SPRING_MAIL_PASSWORD`, AI 키류(`GEMINI_API_KEY` 등), Bedrock/Vertex ID류.
- 실제 값은 `terraform.tfvars`(`.gitignore`) 관리, 변수에 `sensitive = true`. state 는 KMS 암호화.

---

## 8. 배포 / 운영 주의사항

### 배포 순서: Seoul → Ohio → Global
(global 이 seoul/ohio 의 ALB ARN·zone_id 등을 remote state 로 참조)

### destroy 순서: Global → Ohio → Seoul
(GA 가 ALB 참조, 오하이오 RDS Replica 가 서울 RDS Primary 참조 → 역순)

### 함정 모음
- `kubernetes` provider **2.38.0 고정** / `kubectl` gavinbunney 사용(`kubernetes_manifest` 대신 `kubectl_manifest`) / `wait_for_rollout = false`.
- `stockops-secret` 은 ESO 가 관리(수동 생성 불필요). apply 직후 `kubectl get secret stockops-secret -n stockops` 로 동기화 확인(없으면 api-server CrashLoopBackOff).
- TargetGroupBinding `targetType: ip` immutable — 변경 시 삭제 후 재생성.
- IoT 인증서는 `var.iot_certificate_arn` 외부 참조(의도된 설계) → destroy 사이클에서 변경 금지.
- destroy 시: IoT policy/Thing 을 인증서에서 먼저 수동 detach, ArgoCD CRD kubectl 에러는 무시 가능, RDS 파라미터 그룹은 인스턴스 삭제 후 삭제, ECR 은 `data` 참조라 안전.
- PowerShell ECR 로그인: `aws ecr get-login-password | Out-File -Encoding ascii` 후 파일을 `docker login` 에 전달(파이프 직접 전달 시 토큰 인코딩 깨짐).
- 인증서/키 추출 시 BOM 주의 → `[System.IO.File]::WriteAllText(...)`.

---

## 9. 로드맵 (남은 과제)

| 항목 | 우선순위 |
|------|----------|
| AI 기능 활성화 (Bedrock/Gemini/Vertex 중 택1, Model Access + IRSA/키) | 높음 |
| 나머지 센서(온습도/공기질) 등록 + 임계치 알림 로직 | 높음 |
| 오하이오 SQS 컨슈머 검증(failover) + 오하이오 sensor_devices 등록 | 중간 |
| ArgoCD 앱 구성 (GitOps CD) | 중간 |
| DR Lambda 함수 배포 + EventBridge 타깃 연결 (현재 주석) | 중간 |
| 시크릿 평문 입력 개선 (tfvars → Secrets Manager data source / random_password) | 중간 |
| 서울 RDS Multi-AZ 활성화 (현재 주석) | 중간 |
| Azure 트랜잭션 로그 백업 고도화 (3차 방어) | 낮음 |
| Observability 스택 (Grafana/Prometheus) | 낮음 |

---

*최종 업데이트: 2026-06-29 / ALB idle_timeout=120s 추가, GA Ohio 엔드포인트 그룹 주석 처리(서울 only), peering/ 디렉토리 및 state 구조 반영, regions/ 디렉토리 구조 정정*
