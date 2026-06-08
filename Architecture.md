# StockOps — 멀티 하이브리드 클라우드 인프라 아키텍처

> **팀명**: 시선 (SysSun — System Surveillance & Unified Network)
> **프로젝트 주제**: AX 환경을 위한 ERP 솔루션 기반 멀티 하이브리드 클라우드 인프라 자동화 및 Observability 체계 구축
> **애플리케이션**: StockOps

---

## 1. 프로젝트 개요

StockOps는 AX(AI Transformation) 환경의 ERP 솔루션으로, 멀티 리전·하이브리드 클라우드 위에서 동작한다. 인프라 자동화(IaC)와 장애 내결함성 확보를 핵심 목표로 한다.

비즈니스 맥락은 K-Food(예: 비비고 만두)의 해외 수요 증가다. 서울 본사가 운영을 총괄하고, 미국 영업팀이 현지 영업을 지원한다. 영업팀은 본사 운영에 지장을 주지 않도록 최소 권한으로 애플리케이션과 DB에 접근한다.

---

## 2. 인프라 분포

| 위치 | 역할 |
|------|------|
| AWS 서울 리전 | 본사. 한국 사용자 메인 서비스 (풀스택) |
| AWS 오하이오 리전 | 미국 영업팀 서비스 (풀스택 미러) |
| 온프레미스 (한국) | 센터/창고. 센서 데이터 수집 |
| Azure 서울 | 백업/로그 저장 (재해 복구용, 예정) |

---

## 3. 데이터 전략 (3단계 방어)

```
1차 방어 — Multi-AZ (서울 내 AZ 장애)
    서울 RDS Primary ↔ Standby 자동 전환 (다운타임 1~2분)

2차 방어 — Cross-Region Replica (서울 리전 전체 장애)
    서울 RDS (Master) → 오하이오 RDS (Read Replica) 실시간 복제
    리전 장애 시 오하이오 Promote → Master 승격

3차 방어 — Azure 트랜잭션 로그 백업 (AWS 전체 마비)
    5~10분 주기로 트랜잭션 로그 → Azure Blob
    AWS 전체 장애 시 Azure에서 복구 (RPO 최대 10분)
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
| 3차 Azure 백업 | AWS 전체 | 수 시간 (수동) | 최대 10분 |

> Promote 자동화(RDS Event → SNS → Lambda)는 추후 과제. 현재는 수동.

---

## 4. 트래픽 / 라우팅 전략

```
한국/미국 사용자
    └─ Global Accelerator (DNS: *.awsglobalaccelerator.com)
         ├─ 지연 기반: 한국 → 서울 ALB, 미국 → 오하이오 ALB
         └─ 헬스체크 실패 시 다른 리전으로 자동 페일오버
```

- GA 리스너: TCP:80
- 엔드포인트 그룹: 서울(ap-northeast-2) + 오하이오(us-east-2), 각 traffic_dial 100%
- GA는 리전 라우팅, ALB는 서비스 분기(경로/호스트 기반) 담당 — 역할 분리

---

## 5. 온프레미스 연동 (센서 데이터 파이프라인)

```
[온프레미스 창고 센서 — sensormqtt.ithans.com]
        │ Mosquitto 브리지 (TLS:8883) ← 설정 대기 중
        ▼
   [AWS IoT Core — 서울]
   Topic: sensimul/sites/+/sensors/+
        │ IoT Rule
        ▼
   [SQS: stockops-sensor-data] [DLQ: stockops-sensor-data-dlq]
        │
        ▼
   [백엔드 / AI 모듈 — 데이터 분석]
```

현장 ID: `TEST_INDOOR_01` / 센서 7종: TEMP, HUM, PM25, PM10, PRESSURE, DOOR, PRESENCE

> IoT는 서울에만 구성 (센서가 한국 온프레미스에 위치). Site-to-Site VPN 없이 직접 TLS 연결.
> 추후 IoT Rule에 S3 Action 추가하여 영구 저장 + Athena 분석 검토 (회의 결정 대기).

---

## 6. 애플리케이션 구성 (Stockops-Application — 모노레포)
https://github.com/jinuuuKim/Stockops-Application

| 컴포넌트 | 설명 | 포트 |
|----------|------|------|
| `stockops-client-web` | 사용자 포털 (React + nginx) | 80 |
| `stockops-admin-web` | 관리자 웹 (React + nginx) | 80 |
| `stockops-api-server` | 메인 백엔드 (Spring Boot 3.2.12, Java 21) | 8080 |
| `stockops-ai-module` | AI 수요 예측 (FastAPI) | 8000 |

### CI/CD

```
GitHub Actions (CI)
    └─ main push / workflow_dispatch
         └─ Build → 서울 ECR Push (OIDC, 액세스 키 없음)
              └─ ECR Replication → 오하이오 ECR 자동 복제

ArgoCD (CD) — 설치 완료, 앱 구성 예정
```

- OIDC 인증: `role-to-assume` 방식. 액세스 키 없음.
- Terraform이 ECR(그릇)을 만들고, GitHub Actions가 이미지(내용물)를 채운다.

### 주요 설정 노트
- Spring 프로파일: 현재 `dev` + RDS
- 필수 환경변수: `JWT_SECRET`, `STOCKOPS_DATASOURCE_URL/USERNAME/PASSWORD`, `SPRING_DATA_REDIS_HOST`
- Spring 헬스체크: `/actuator/health` (Redis 필수), FastAPI: `/health`
- API prefix: `/api/v1/...`
- 초기 admin: `admin@stockops.com` / `admin123`

---

## 7. 인프라 구성 (Stockops-Infra — Terraform)

### 디렉토리 구조
```
Stockops-Infra/
├── modules/          # 공통 모듈
│   ├── alb/          # ALB + Target Groups
│   ├── db/           # RDS PostgreSQL
│   ├── ecr/          # ECR 리포 (for_each)
│   ├── eks/          # EKS + 노드그룹 + IRSA(LBC) + OIDC
│   ├── github-oidc/  # GitHub Actions OIDC Provider + IAM Role
│   ├── iot/          # IoT Thing + 인증서 + Rule + SQS + DLQ
│   └── vpc/          # VPC + 3-Tier Subnets
├── seoul/            # 서울 리전 (풀스택 + IoT + ECR 원본 + GitHub OIDC)
├── ohio/             # 오하이오 리전 (풀스택 미러 + RDS Read Replica)
└── global/           # Global Accelerator
```

### Terraform State (S3 backend)

```
siseon-terraform-state/
└── infra/
    ├── seoul/terraform.tfstate
    ├── ohio/terraform.tfstate
    └── global/terraform.tfstate
```

> global은 `terraform_remote_state`로 seoul/ohio의 ALB ARN을 동적 참조.

### 네트워크

| 리전 | VPC CIDR | Public | Private App | Private DB |
|------|----------|--------|-------------|------------|
| 서울 | 10.0.0.0/16 | 10.0.1~2.0/24 | 10.0.11~12.0/24 | 10.0.21~22.0/24 |
| 오하이오 | 10.1.0.0/16 | 10.1.1~2.0/24 | 10.1.11~12.0/24 | 10.1.21~22.0/24 |

### EKS
- 서울: `seoul-cluster` / 오하이오: `ohio-cluster` (둘 다 v1.30, t3.medium×2)
- AWS Load Balancer Controller (IRSA + OIDC) — helm_release
- TargetGroupBinding으로 ALB ↔ Pod 연결 (`targetType: ip`, immutable)
- `kubectl_manifest`(gavinbunney/kubectl) → plan-time 검증 회피, `depends_on=LBC`
- Deployment `wait_for_rollout = false`
- Redis는 클러스터 내 Pod (redis:7-alpine)

### ALB 라우팅 (현행: 경로 기반)

| 경로 | 대상 |
|------|------|
| `/` (default) | client-web |
| `/admin`, `/admin/*` | admin-web |
| `/api`, `/api/*` | Spring API |
| `/ai`, `/ai/*` | FastAPI |

> Route 53 + ACM 도입 시 호스트 기반(`stockops.live` / `admin.stockops.live`)으로 전환 예정. admin 서브패스 쿠키 문제 해결.

### 시크릿 관리 (ESO)

```
Secrets Manager (stockops/app)
    └─ ClusterSecretStore → ExternalSecret (1h)
         └─ K8s Secret (stockops-secret) 자동 생성 → 파드 주입
```

- ESO IRSA(`stockops-eso-role`)로 Secrets Manager 접근
- `terraform.tfvars`에서 값 관리, `.gitignore` Git 비추적
- DB 모듈 변수 기본값 제거 → 루트에서 `var` 주입 (Secrets Manager 일관성)

---

## 8. 배포/운영 주의사항

### 배포 순서
1. 서울 (2단계: 인프라 → kubeconfig → 풀 apply)
2. 오하이오 (Cross-Region Replica 20~40분 소요)
3. 글로벌 (GA)

### destroy 순서
global → ohio → seoul (GA가 ALB 참조, 오하이오 Replica가 서울 RDS 참조)

### 함정 모음
- `kubernetes` provider 2.38 고정 (identity 버그)
- TargetGroupBinding `targetType` immutable — 변경 시 삭제 후 재생성
- ALB 헬스체크: Spring `/actuator/health`, FastAPI `/health`
- PowerShell 멀티 인자 `--%` 연산자
- 인증서 추출 시 BOM 주의 → Python `open().write()`
- destroy 후 재apply 시 IoT 인증서 새로 발급 → 브리지 재설정
- GitHub provider 다운로드 504 시 서울 `.terraform/providers` 복사 후 `-lockfile=readonly`
- SSO 토큰 세션 7일로 연장 설정 완료

---

## 9. 추가 예정 서비스

| 서비스 | 용도 | 우선순위 |
|--------|------|----------|
| Route 53 + ACM | DNS + TLS + 호스트 분리 (stockops.live) | 높음 |
| WAF | ALB/GA 앞단 보안 | 중간 |
| ArgoCD 앱 구성 | GitOps CD | 중간 |
| IoT 브리지 연결 | 온프레미스 Mosquitto → IoT Core | 중간 |
| 서울 RDS Multi-AZ | 1차 방어 활성화 | 중간 |
| Azure 트랜잭션 로그 백업 | 3차 방어 | 낮음 |
| Observability | 모니터링 스택 | 낮음 |

---

*최종 업데이트: 2026-06-08 / 오하이오 멀티 리전 풀스택, Cross-Region RDS Replica, Global Accelerator, ArgoCD 설치, state seoul/ohio/global 분리 완료*
