# ==========================================================================
# 글로벌 리소스 — 프로바이더 및 백엔드 설정
# ==========================================================================
# 변경점: CloudFront 인증서(ACM)는 반드시 us-east-1 에 있어야 하므로
#         virginia 별칭 프로바이더 추가. S3 프론트 버킷도 여기 생성.
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

# 기본 프로바이더 — Global Accelerator 관리 리전
provider "aws" {
  region  = "us-west-2"
  profile = "siseon"
}

# CloudFront용 ACM 인증서 (반드시 us-east-1)
provider "aws" {
  alias   = "virginia"
  region  = "us-east-1"
  profile = "siseon"
}

# 기존 프론트 버킷이 위치한 리전 (버킷 정책/PAB 적용용)
# ※ 버킷이 us-east-1 이 아니면 var.frontend_bucket_region 을 실제 리전으로 설정
provider "aws" {
  alias   = "frontend"
  region  = var.frontend_bucket_region
  profile = "siseon"
}
