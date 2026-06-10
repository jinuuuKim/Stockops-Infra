# ==========================================================================
# 오하이오 리전 메인 — 모듈 호출 진입점
# ==========================================================================

module "ohio_vpc" {
  source               = "../modules/vpc"
  region_name          = "ohio"
  az_a                 = "us-east-2a"
  az_c                 = "us-east-2c"
  vpc_cidr             = "10.1.0.0/16"
  pub_sub_2a_cidr      = "10.1.1.0/24"
  pub_sub_2c_cidr      = "10.1.2.0/24"
  priv_app_sub_2a_cidr = "10.1.11.0/24"
  priv_app_sub_2c_cidr = "10.1.12.0/24"
  priv_db_sub_2a_cidr  = "10.1.21.0/24"
  priv_db_sub_2c_cidr  = "10.1.22.0/24"
}

module "ohio_alb" {
  source              = "../modules/alb"
  region_name         = "ohio"
  vpc_id              = module.ohio_vpc.vpc_id
  public_subnet_ids   = module.ohio_vpc.public_subnet_ids
  acm_certificate_arn = aws_acm_certificate_validation.ohio.certificate_arn
  domain              = var.domain
}

module "ohio_eks" {
  source              = "../modules/eks"
  region_name         = "ohio"
  vpc_id              = module.ohio_vpc.vpc_id
  priv_app_subnet_ids = module.ohio_vpc.priv_app_subnet_ids
  app_sg_id           = aws_security_group.ohio_app_sg.id
  db_sg_id            = aws_security_group.ohio_db_sg.id
  frontend_tg_arn     = module.ohio_alb.frontend_tg_arn
  spring_tg_arn       = module.ohio_alb.spring_tg_arn
  fastapi_tg_arn      = module.ohio_alb.fastapi_tg_arn
  node_desired = 1
  node_min     = 1
  node_max     = 4
}

# RDS Read Replica (서울 Master → 오하이오 Replica)
resource "aws_db_instance" "ohio_replica" {
  identifier             = "ohio-rds-postgres"
  replicate_source_db    = "arn:aws:rds:ap-northeast-2:448768137813:db:${var.seoul_db_identifier}"
  instance_class         = "db.t4g.micro"
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.ohio_db_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.ohio.name
  skip_final_snapshot    = true
  backup_retention_period = 7

  tags = {
    Name = "ohio-rds-postgres"
  }
}

resource "aws_db_subnet_group" "ohio" {
  name       = "ohio-db-subnet-group"
  subnet_ids = module.ohio_vpc.priv_db_subnet_ids

  tags = {
    Name = "ohio-db-subnet-group"
  }
}

data "aws_caller_identity" "current" {}