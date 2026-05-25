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

# 3. 서울 ECS Fargate 클러스터 및 애플리케이션 가동 환경 배포 (컴퓨팅)
module "seoul_ecs" {
  source              = "../modules/ecs"
  region_name         = "seoul"
  vpc_id              = module.seoul_vpc.vpc_id
  priv_app_subnet_ids = module.seoul_vpc.priv_app_subnet_ids
  app_sg_id           = aws_security_group.seoul_app_sg.id
  spring_tg_arn       = module.seoul_alb.spring_tg_arn
  fastapi_tg_arn      = module.seoul_alb.fastapi_tg_arn
}

# 4. 서울 RDS PostgreSQL 데이터베이스 인프라 배포 (데이터 - 신규 연동)
module "seoul_db" {
  source             = "../modules/db"
  region_name        = "seoul"
  priv_db_subnet_ids = module.seoul_vpc.priv_db_subnet_ids
  db_sg_id           = aws_security_group.seoul_db_sg.id      # seoul/security_groups.tf 에서 생성된 SG 연동
}

# ==========================================================================
# 최종 결과값 터미널 화면 출력 (Outputs)
# ==========================================================================

output "seoul_alb_dns" {
  description = "프로젝트 서울 리전 메인 웹 진입 주소"
  value       = module.seoul_alb.alb_dns_name
}

output "seoul_database_host" {
  description = "RDS 접속 엔드포인트 주소"
  value       = module.seoul_db.db_address
}