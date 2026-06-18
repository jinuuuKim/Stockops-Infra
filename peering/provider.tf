# ==========================================================================
# 피어링 모듈 — 프로바이더 및 백엔드 설정
# Seoul ↔ Ohio VPC 피어링 전용 state (seoul/ohio 양쪽 apply 완료 후 apply)
# ==========================================================================

terraform {
  backend "s3" {
    bucket       = "siseon-terraform-state"
    key          = "infra/peering/terraform.tfstate"
    region       = "ap-northeast-2"
    profile      = "siseon"
    encrypt      = true
    kms_key_id   = "alias/siseon-tfstate"
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "ap-northeast-2"
  profile = "siseon"
}

provider "aws" {
  alias   = "ohio"
  region  = "us-east-2"
  profile = "siseon"
}
