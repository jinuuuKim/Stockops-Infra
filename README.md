# 🛒 StockOps - 식품 ERP 멀티 클라우드 인프라

![Terraform](https://img.shields.io/badge/terraform-%235843U9.svg?style=for-the-badge&logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-%23316192.svg?style=for-the-badge&logo=postgresql&logoColor=white)
![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/github%20actions-%232088FF.svg?style=for-the-badge&logo=githubactions&logoColor=white)

본 저장소는 멀티 리전 및 멀티 클라우드 아키텍처를 기반으로 하는 **식품 ERP 애플리케이션(StockOps)**의 AWS 서울 리전 메인 프로덕션 인프라 테라폼(Terraform) 소스 코드입니다. 

1단계 인프라 고가용성 뼈대 구축을 완벽하게 마감하고, 현재 **실제 상용 애플리케이션 이식, External Secrets Operator(ESO) 보안 체계 도입 및 GitHub Actions 기반의 풀 오토메이션 CI/CD 파이프라인** 환경을 결합하는 고도화 단계(2단계)를 성공적으로 수행하고 있습니다.

---

## ✨ 핵심 아키텍처 특징

* **고가용성 네트워크 (VPC Multi-AZ):** 서울 리전(`ap-northeast-2`) 내 가용영역 2개(`2a`, `2c`)를 분할 활용하여 단일 데이터 센터 물리 장애에 대응하는 결함 허용(Fault-Tolerant) 아키텍처를 확립했습니다.
* **쿠버네티스 오케스트레이션 (Amazon EKS):** 복잡한 컨테이너 생명주기를 안정적으로 관리하기 위해 Amazon EKS Managed Node Group을 도입했습니다. AWS 로드 밸런서 컨트롤러를 연동하여 가상 머신 제약이 없는 유연한 컨테이너 토폴로지를 제공합니다.
* **IP 타겟 기반 L7 경로 분기 (ALB):** 단일 애플리케이션 로드 밸런서가 프라이빗 서브넷에 상주하는 개별 Pod의 사설 IP 주소로 트래픽을 정밀 타격하여 다이렉트 포워딩하는 `ip` 모드 라우팅을 채택했습니다. URL 경로 패턴에 따라 클라이언트 웹, 관리자 대시보드, 메인 API, AI 모듈로 완벽히 분기합니다.
* **스토리지 자동 확장 데이터베이스 (RDS):** 외부 접근이 원천 차단된 사설 DB 서브넷 위에서 구동되는 고성능 RDS PostgreSQL입니다. 스마트 창고 센서 데이터 대량 유입 시 발생할 수 있는 디스크 용량 부족을 방지하기 위해 중단 없는 **스토리지 자동 확장(최대 100GB)** 인프라 기술을 결합했습니다.

---

## 🔄 2단계: 프로덕션 애플리케이션 및 풀 오토메이션 가동 규격

실제 운영 환경의 명세와 협업 파이프라인을 구축하기 위해 아래의 고도화 사양을 인프라에 완전 동기화했습니다.

### 1. 실서비스 전용 독립 네임스페이스 격리
기존 `default` 공간의 보안 취약성을 극복하고 자원을 효율적으로 격리하기 위해 쿠버네티스 내부에 **`stockops`** 독립 네임스페이스를 개설하여 모든 상용 컴포넌트를 이중 보호합니다.

### 2. 4대 마이크로서비스(MSA) 세부 라우팅 명세
| URL 경로 패턴 | 연결 대상 컴포넌트 | 구동 포트 | 채택 기술 스택 |
| :--- | :--- | :--- | :--- |
| `http://ALB주소/` | **stockops-client-web** (사용자 포털) | 80 | React + Vite, Nginx |
| `http://ALB주소/admin` | **stockops-admin-web** (관리자 웹) | 80 | React + Vite, Nginx |
| `http://ALB주소/api` | **stockops-api-server** (백엔드 API) | 8080 | Spring Boot 3, Java 21 |
| `http://ALB주소/ai` | **stockops-ai-module** (AI 재고 예측) | 8000 | Python FastAPI, Prophet |

### 3. 클라우드 네이티브 보안 자격증명 연동 (ESO)
쿠버네티스 파일에 DB 패스워드나 JWT 시크릿 키를 하드코딩하는 위험을 제거하기 위해 테라폼에 Helm 공급자를 결합하여 **`External Secrets Operator (ESO)`**를 자동 프로비저닝했습니다. 이를 통해 AWS Secrets Manager 내부의 기밀 데이터를 EKS 내부 Secret 자원으로 안전하게 실시간 미러링 동기화합니다.

---

## 🔒 방화벽 신뢰 사슬 및 규칙 충돌 원천 차단

리소스 간의 보안 그룹(Security Group) 소스 참조 방식을 채택하였으며, 테라폼 엔진의 특성으로 인한 인프라 불안정성을 해결하기 위해 **100% 독립형 리소스 규칙(`aws_security_group_rule`) 분리 기법**으로 재설계했습니다.

* **Flapping(덮어쓰기 경쟁) 해결:** 인라인 `ingress` 블록과 외부 리소스의 혼용을 완전 차단하여 AWS API 레이어의 방화벽 규칙 꼬임 현상을 무결점 방어했습니다.
* **EKS 실제 방화벽 주입:** `target_type = "ip"` 구조에 맞추어 규칙의 목적지를 유령 방화벽이 아닌, 워커 노드들이 실제 착용하고 있는 **EKS 클러스터 고유 보안 그룹 ID(`cluster_security_group_id`)**로 정밀 타격 매핑했습니다.

```text
[외부 인터넷 트래픽] 
       │
       ▼ (HTTP 80 / HTTPS 443 인바운드 성문 개방)
┌────────────────────────────────────────────────────────┐
│ 1. 로드 밸런서 보안 그룹 (seoul-alb-sg)                │
│    - 프라이빗 Pod IP 타겟 노크를 위해 Egress 전면 개방   │
└──────────────────────────┬─────────────────────────────┘
                           │
                           ▼ (오직 seoul-alb-sg를 통과한 패킷만 허용)
┌────────────────────────────────────────────────────────┐
│ 2. EKS 클러스터 실제 노드 방화벽 (Cluster Security Group) │
│    - Client/Admin(80), Spring(8080), FastAPI(8000)     │
└──────────────────────────┬─────────────────────────────┘
                           │
                           ▼ (오직 노드 방화벽 소스 및 VPC 사설망만 수용)
┌────────────────────────────────────────────────────────┐
│ 3. 데이터베이스 보안 그룹 (seoul-db-sg)                 │
│    - RDS PostgreSQL (Port: 5432) 완전 격리 및 보호     │
└────────────────────────────────────────────────────────┘
```

## 📂 디렉터리 구조 및 파일 역할 설명
stockops-infra/
├── .github/
│   └── workflows/
│       └── deploy.yml        # ⚙️ GitHub Actions CI/CD 마스터 파이프라인 명세서
├── mock-ai/                  # [Mock FastAPI]
├── mock-frontend/                  # [Mock Frontend]
├── mock-backend/                  # [Mock Backend]
├── modules/                  # [공통 인프라 패키지 틀] - 재사용 가능 모듈
│   ├── vpc/                  # - 순수 고가용성 네트워크망 구성 모듈
│   ├── alb/                  # - 순수 로드 밸런서 및 L7 경로 분기 규칙 모듈
│   ├── eks/                  # - EKS Core 및 컴퓨팅 클러스터 관리 모듈
│   └── db/                   # - 스토리지 자동 확장형 사설 데이터베이스 모듈
│   └── ecr/                  # - 프라이빗 ECR 레포지토리
└── seoul/                    # [서울 리전 실제 배포 구역] - 실행 센터
    ├── provider.tf           # - AWS 공급자 및 Helm/Kubernetes 자격증명 정의
    ├── main.tf               # - 모듈들을 순서대로 호출하여 조립하는 마스터 파일
    ├── security_groups.tf    # - 완벽하게 분리된 독립형 방화벽 규칙 집중 관리 파일
    └── kubernetes.tf         # - stockops 네임스페이스 및 실서비스 Pod 명세 제어 파일