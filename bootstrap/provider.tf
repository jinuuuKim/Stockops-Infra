# ==========================================================================
# bootstrap — state 버킷/KMS/락을 관리하는 별도 구성
# ※ 이 구성은 "원격 state 버킷 자체"를 다루므로 로컬 백엔드를 쓴다(닭-달걀).
#    bootstrap 자신의 state(terraform.tfstate)는 로컬에 남으며, 시크릿 없음.
# ==========================================================================
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # 의도적으로 backend 미지정 = 로컬 백엔드
}

provider "aws" {
  region  = "ap-northeast-2" # state 버킷이 있는 리전
  profile = "siseon"
}

data "aws_caller_identity" "current" {}

locals {
  state_bucket = "siseon-terraform-state"
}
