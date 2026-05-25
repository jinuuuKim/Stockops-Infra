# 🛒 StockOps - 식품 ERP 멀티 클라우드 인프라 (1단계)

![Terraform](https://img.shields.io/badge/terraform-%235843U9.svg?style=for-the-badge&logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-%23316192.svg?style=for-the-badge&logo=postgresql&logoColor=white)
![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)

본 저장소는 멀티 리전(Seoul/Tokyo) 및 멀티 클라우드(AWS/Azure) 아키텍처를 기반으로 하는 **식품 ERP 애플리케이션(StockOps)**의 AWS 서울 리전 메인 인프라 테라폼(Terraform) 소스 코드입니다. 

1단계 목표인 **최소한의 기본 인프라 구조 설계 및 고가용성 뼈대 구축**을 완벽하게 반영하였으며, 자원의 생명 주기(Lifecycle)에 따라 독립적으로 분리된 **느슨한 결합(Loose Coupling) 모듈 구조**를 채택하였습니다.

---

## ✨ 1단계 핵심 아키텍처 특징

* **고가용성 네트워크 (VPC Multi-AZ):** 서울 리전(`ap-northeast-2`) 내 가용영역 2개(`2a`, `2c`)를 활용한 이중화 배치로 단일 데이터 센터 장애에 대응하는 Fault-Tolerant 구조를 확립했습니다.
* **3-Tier 보안 격리:** 퍼블릭(Public), 프라이빗 애플리케이션(Private App), 프라이빗 데이터베이스(Private DB) 레이어로 사설망을 3중 분할하여 중요 자원을 인터넷 위협으로부터 격리했습니다.
* **L7 경로 기반 라우팅 (ALB):** 단일 애플리케이션 로드 밸런서를 통해 트래픽을 지능적으로 분기합니다. `/ai/*` 주소의 요청은 FastAPI AI 분석 서버로, 그 외 모든 일반 요청은 Spring API 메인 백엔드로 자동 라우팅됩니다.
* **서버리스 컨테이너 컴퓨팅 (ECS Fargate):** EC2 서버 관리 및 가상 머신 스케일링 부담이 없는 Fargate 엔진을 탑재했습니다. 각 태스크 컨테이너는 `awsvpc` 모드로 사설 IP를 직접 할당받아 네트워크 보안성을 극대화합니다.
* **스토리지 자동 확장 데이터베이스 (RDS):** 외부 접근이 완벽히 차단된 사설 DB 서브넷 위에서 구동되는 RDS PostgreSQL입니다. 스마트 창고 센서 데이터 유입으로 인한 용량 부족을 방지하기 위해 중단 없는 **스토리지 자동 확장(최대 100GB)** 기술을 활성화했습니다.

---

## 🔒 방화벽 신뢰 사슬 (Chain of Trust) 구조

외부 개방을 최소화하고 리소스 간의 **보안 그룹(Security Group) 소스 참조 방식**을 채택하여 강력한 인바운드 통제 메커니즘을 구현했습니다.

```text
[외부 인터넷 트래픽] 
       │
       ▼ (HTTP 80 / HTTPS 443 오직 이 문만 전면 개방)
┌────────────────────────────────────────────────────────┐
│ 1. 로드 밸런서 보안 그룹 (seoul-alb-sg)                │
└──────────────────────────┬─────────────────────────────┘
                           │
                           ▼ (오직 seoul-alb-sg를 통과한 트래픽만 허용)
┌────────────────────────────────────────────────────────┐
│ 2. 애플리케이션 보안 그룹 (seoul-app-sg)               │
│    - Spring API (Port: 8080) / FastAPI AI (Port: 8000) │
└──────────────────────────┬─────────────────────────────┘
                           │
                           ▼ (오직 seoul-app-sg를 소스로 가진 트래픽만 허용)
┌────────────────────────────────────────────────────────┐
│ 3. 데이터베이스 보안 그룹 (seoul-db-sg)                │
│    - RDS PostgreSQL (Port: 5432) 완전 격리             │
└────────────────────────────────────────────────────────┘
```

---

## 📂 디렉터리 구조 및 파일 역할 설명

```text
stockops-infra/
├── modules/                  # [공통 인프라 붕어빵 틀] - 재사용 가능한 패키지
│   ├── vpc/                  # 1. 순수 네트워크망 모듈
│   │   ├── variables.tf      #    - 리전별 CIDR 블록 및 AZ 변수 정의
│   │   ├── main.tf           #    - VPC, 서브넷 6개, IGW, NAT GW, 라우팅 테이블 제어
│   │   └── outputs.tf        #    - 생성된 VPC 및 서브넷 ID 그룹 외부 반환
│   ├── alb/                  # 2. 순수 로드 밸런서 모듈
│   │   ├── variables.tf      #    - 네트워크 정보 수령 변수
│   │   ├── main.tf           #    - ALB, Target Group 2종, 경로 분기 리스너 규칙 정의
│   │   └── outputs.tf        #    - ALB DNS 주소 및 ALB SG ID 외부 반환
│   ├── ecs/                  # 3. 컨테이너 오케스트레이션 모듈
│   │   ├── variables.tf      #    - 방화벽 ID 및 타겟 그룹 ARN 수령 변수
│   │   ├── main.tf           #    - Fargate 클러스터, Task 정의(로그그룹 연동), 서비스 가동
│   │   └── outputs.tf        #    - 클러스터명 출력
│   └── db/                   # 4. 데이터베이스 인프라 모듈
│       ├── variables.tf      #    - DB 마스터 계정 세팅 및 SG 수령 변수
│       ├── main.tf           #    - DB 서브넷 그룹 및 Graviton 기반 rds 인스턴스 정의
│       └── outputs.tf        #    - DB 접속 엔드포인트 호스트 주소 외부 반환
│
└── seoul/                    # [서울 리전 실제 배포 구역] - 실행 센터
    ├── provider.tf            # AWS ap-northeast-2 공급자 정의
    ├── main.tf                # 위의 4개 모듈을 순서대로 불러와 유기적으로 조립하여 인프라를 완성하는 마스터 파일
    └── security_groups.tf     # 앱 및 DB에 적용될 핵심 방화벽 체인을 집중 관리하는 파일
```

---

## 🚀 인프라 실행 방법 및 순서

### 1. 사전 요구사항 (Prerequisites)
* 로컬 컴퓨터에 **Terraform** 및 **AWS CLI**가 설치되어 있어야 합니다.
* 터미널에서 아래 명령어를 통해 인프라 프로비저닝 권한을 가진 IAM 계정 로그인을 선행합니다.
  ```bash
  aws configure
  ```

### 2. 초기화 및 배포 절차
> ⚠️ **중요 실행 규칙:** 테라폼 명령어는 공통 틀이 자리를 잡고 있는 `modules/` 폴더가 아니라, 실제 배포의 중심인 **`seoul/` 폴더로 이동하여 실행**해야 합니다. 리전 실행 폴더에서 명령어를 호출하면 테라폼이 상위 모듈 폴더를 자동으로 읽어와 사설 인프라를 안전하게 빌드합니다.

```bash
# 1단계: 서울 리전 배포 제어 폴더로 이동
cd seoul

# 2단계: 공급자 플러그인 및 작성된 상위 모듈 초기화
terraform init

# 3단계: 가상 설계도 미리보기 및 변수 매핑 상태 검토
terraform plan

# 4단계: 실제 AWS 클라우드 인프라 생성 프로비저닝 시작
terraform apply
# (터미널 창에 'yes'를 입력해야 최종 승인 및 생성이 진행됩니다)
terraform apply -auto-approve
# ('yes'입력 생략)
```

### 3. 자원 해제 및 비용 관리 (Teardown)
실습 및 테스트가 끝나고 자원을 안전하게 파기하여 불필요한 비용 청구를 방지하려면 아래 명령어를 수행합니다.
```bash
# 생성된 모든 AWS 리소스를 안전하게 역순으로 완전 파기
terraform destroy
```

---