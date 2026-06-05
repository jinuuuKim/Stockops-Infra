# seoul/provider.tf 파일 전체 교체 코드 (진짜 이름 seoul-cluster 적용 버전)

terraform {
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
  region = "ap-northeast-2"
  profile = "siseon"
}

# --------------------------------------------------------------------------
# 쿠버네티스 프로바이더 설정 (실제 이름 seoul-cluster 동적 토큰 발행)
# --------------------------------------------------------------------------
provider "kubernetes" {
  # 개발자님이 소지하신 EKS 모듈의 실제 물리 엔드포인트와 CA 데이터를 직통 매핑합니다.
  host                   = module.seoul_eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.seoul_eks.cluster_ca_certificate)

  # 🌟 [에러 완벽 해결] 클러스터 이름을 실제 이름인 seoul-cluster로 정확히 매핑하여 토큰을 굽습니다.
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", "seoul-cluster", "--profile", "siseon"]
  }
}

# --------------------------------------------------------------------------
# 헬름 프로바이더 설정 (동일 구조 적용으로 보안 무결성 확보)
# --------------------------------------------------------------------------
provider "helm" {
  kubernetes {
    host                   = module.seoul_eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.seoul_eks.cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", "seoul-cluster", "--profile", "siseon"]
    }
  }
}

provider "kubectl" {
  host                   = module.seoul_eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.seoul_eks.cluster_ca_certificate)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", "seoul-cluster", "--profile", "siseon"]
  }
}