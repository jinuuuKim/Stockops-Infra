# ==========================================================================
# 오하이오 리전 — 프로바이더 및 백엔드 설정
# ==========================================================================

terraform {
  backend "s3" {
    bucket  = "siseon-terraform-state"
    key     = "infra/ohio/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "siseon"
    encrypt      = true                  # state at-rest 암호화 ON
    kms_key_id   = "alias/siseon-tfstate" # bootstrap 이 만든 KMS 별칭
    use_lockfile = true                  # TF 1.10+ S3 네이티브 락
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}

provider "aws" {
  region  = "us-east-2"
  profile = "siseon"
}

provider "aws" {
  alias   = "ohio"
  region  = "us-east-2"
  profile = "siseon"
}

provider "kubernetes" {
  host                   = module.ohio_eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.ohio_eks.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", "ohio-cluster", "--profile", "siseon"]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.ohio_eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.ohio_eks.cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", "ohio-cluster", "--profile", "siseon"]
    }
  }
}

provider "kubectl" {
  host                   = module.ohio_eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.ohio_eks.cluster_ca_certificate)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", "ohio-cluster", "--profile", "siseon"]
  }
}