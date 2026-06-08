# ==========================================================================
# 글로벌 리소스 — 프로바이더 및 백엔드 설정
# Global Accelerator는 us-west-2 리전에서 관리됩니다.
# ==========================================================================

terraform {
  backend "s3" {
    bucket  = "siseon-terraform-state"
    key     = "infra/global/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "siseon"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "us-west-2"
  profile = "siseon"
}