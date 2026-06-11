# ==========================================================================
# 서울 리전 메인 — 모듈 호출 진입점
# ==========================================================================

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
  cluster_name = "seoul-cluster"
}

module "seoul_alb" {
  source              = "../modules/alb"
  region_name         = "seoul"
  vpc_id              = module.seoul_vpc.vpc_id
  public_subnet_ids   = module.seoul_vpc.public_subnet_ids
  acm_certificate_arn = aws_acm_certificate_validation.seoul.certificate_arn
  domain              = var.domain
}

module "seoul_eks" {
  source              = "../modules/eks"
  region_name         = "seoul"
  vpc_id              = module.seoul_vpc.vpc_id
  priv_app_subnet_ids = module.seoul_vpc.priv_app_subnet_ids
  app_sg_id           = aws_security_group.seoul_app_sg.id
  db_sg_id            = aws_security_group.seoul_db_sg.id
  spring_tg_arn       = module.seoul_alb.spring_tg_arn
  fastapi_tg_arn      = module.seoul_alb.fastapi_tg_arn
  node_desired = 2
  node_min     = 2
  node_max     = 4
}

module "seoul_karpenter" {
  source = "../modules/karpenter"

  cluster_name      = "seoul-cluster"
  cluster_endpoint  = module.seoul_eks.cluster_endpoint
  oidc_provider_arn = module.seoul_eks.oidc_provider_arn
  oidc_provider     = module.seoul_eks.oidc_provider
  region_name       = "seoul"
  node_role_arn     = module.seoul_eks.node_role_arn
  create_spot_service_linked_role = true

  depends_on = [module.seoul_eks]
}

module "seoul_db" {
  source             = "../modules/db"
  region_name        = "seoul"
  priv_db_subnet_ids = module.seoul_vpc.priv_db_subnet_ids
  db_sg_id           = aws_security_group.seoul_db_sg.id
  db_username        = var.db_username
  db_password        = var.db_password
}

module "seoul_ecr" {
  source   = "../modules/ecr"
  for_each = toset([
    "stockops-api",
    "stockops-ai",
  ])
  region_name     = "seoul"
  repository_name = each.value
}

data "aws_caller_identity" "current" {}
