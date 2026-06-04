# ==========================================================================
# 서울 리전 인프라 최종 통합 제어 센터 (Main)
# ==========================================================================

# 1. 서울 순수 네트워크망 배포 (VPC & 3-Tier Subnets)
module "seoul_vpc" {
  source               = "../modules/vpc"
  region_name          = "seoul"
  az_a                 = "ap-northeast-2a"
  az_c                 = "ap-northeast-2c"
  vpc_cidr             = "10.0.0.0/16"
  pub_sub_2a_cidr      = "10.0.1.0/24"
  pub_sub_2c_cidr      = "10.0.2.0/24"
  priv_app_sub_2a_cidr = "10.0.11.0/24"
  priv_app_sub_2c_cidr = "10.0.12.0/24"
  priv_db_sub_2a_cidr  = "10.0.21.0/24"
  priv_db_sub_2c_cidr  = "10.0.22.0/24"
}

# 2. 서울 로드 밸런서 배포 (진입로)
module "seoul_alb" {
  source            = "../modules/alb"
  region_name       = "seoul"
  vpc_id            = module.seoul_vpc.vpc_id
  public_subnet_ids = module.seoul_vpc.public_subnet_ids
}

# 3. EKS
module "seoul_eks" {
  source              = "../modules/eks"
  region_name         = "seoul" # 하드코딩 문자열 매핑으로 변수 선언 누락 오류를 완벽히 해결합니다.
  vpc_id              = module.seoul_vpc.vpc_id
  priv_app_subnet_ids = module.seoul_vpc.priv_app_subnet_ids
  app_sg_id           = aws_security_group.seoul_app_sg.id
  db_sg_id            = aws_security_group.seoul_db_sg.id
  frontend_tg_arn     = module.seoul_alb.frontend_tg_arn
  spring_tg_arn       = module.seoul_alb.spring_tg_arn
  fastapi_tg_arn      = module.seoul_alb.fastapi_tg_arn
}

# 4. 서울 RDS PostgreSQL 데이터베이스 인프라 배포 (데이터 - 신규 연동)
module "seoul_db" {
  source             = "../modules/db"
  region_name        = "seoul"
  priv_db_subnet_ids = module.seoul_vpc.priv_db_subnet_ids
  db_sg_id           = aws_security_group.seoul_db_sg.id # seoul/security_groups.tf 에서 생성된 SG 연동
}

# 5. Gitea 소스 코드 빌드 이미지 보관을 위한 서울 ECR 배포 (컨테이너 저장소)
module "seoul_ecr" {
  source   = "../modules/ecr"
  
  # 🌟 테라폼 for_each 기술로 4개의 이름을 순회하며 모듈을 4번 자동 가동합니다.
  for_each = toset([
    "stockops-api",
    "stockops-ai",
    "stockops-admin-web",
    "stockops-client-web"
  ])

  region_name     = "seoul"
  repository_name = each.value # 🌟 순회 중인 이름(예: stockops-api 등)을 모듈에 다이렉트 주입!
}