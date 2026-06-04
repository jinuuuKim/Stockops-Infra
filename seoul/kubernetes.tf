# ==========================================
# 0. 프로바이더 버전 고정 (공식 정품 구성으로 원상 복구)
# ==========================================
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

# ==========================================
# 1. EKS 모듈 출력값을 활용한 동적 프로바이더 초기화 (AWS 정석 exec 인증)
# ==========================================
provider "kubernetes" {
  host                   = module.seoul_eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.seoul_eks.cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.seoul_eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.seoul_eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.seoul_eks.cluster_ca_certificate)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.seoul_eks.cluster_name]
    }
  }
}

# ==========================================
# 2. IRSA 자격 증명 인프라 아키텍처 구현 (OIDC & IAM Role)
# ==========================================
data "tls_certificate" "seoul_eks" {
  url = module.seoul_eks.oidc_issuer
}

resource "aws_iam_openid_connect_provider" "seoul_eks_oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.seoul_eks.certificates[0].sha1_fingerprint]
  url             = module.seoul_eks.oidc_issuer
}

resource "aws_iam_policy" "aws_lb_controller_policy" {
  name        = "seoul-aws-lb-controller-policy"
  path        = "/"
  description = "IAM policy for AWS Load Balancer Controller on EKS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole",
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeValidations",
          "ec2:DescribeVpcs",
          "elasticloadbalancing:*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "aws_lb_controller_role" {
  name = "seoul-aws-lb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.seoul_eks_oidc.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.seoul_eks_oidc.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "aws_lb_controller_attach" {
  policy_arn = aws_iam_policy.aws_lb_controller_policy.arn
  role       = aws_iam_role.aws_lb_controller_role.name
}

# ==========================================
# 3. AWS Load Balancer Controller Helm 자동 설치
# ==========================================
resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = module.seoul_eks.cluster_name
  }

  set {
    name  = "vpcId"
    value = module.seoul_vpc.vpc_id
  }

  set {
    name  = "region"
    value = "ap-northeast-2"
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.aws_lb_controller_role.arn
  }
}

# seoul/kubernetes.tf 파일 하단 영역 교체

# ==========================================
# 4. 인프라 테스트용 메인 백엔드 (Spring 포트 8080 - ECR 실제 이미지 연동)
# ==========================================
resource "kubernetes_deployment_v1" "stockops_spring" {
  metadata {
    name      = "stockops-spring-backend"
    namespace = "default"
    labels    = { app = "stockops-spring" }
  }

  spec {
    replicas = 2
    selector { match_labels = { app = "stockops-spring" } }

    template {
      metadata { labels = { app = "stockops-spring" } }
      spec {
        container {
          name  = "spring-container"
          # 🌟 [ECR 이미지 연동] 방금 푸시하신 백엔드 실제 이미지 주소로 교체합니다.
          image = "247385839803.dkr.ecr.ap-northeast-2.amazonaws.com/seoul-stockops-app-repo:backend"
          
          # 🌟 [포트 정석 복원] 도커파일 명세에 맞춰 내부 8080 포트를 개방합니다.
          port { container_port = 8080 } 
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "stockops_spring_svc" {
  metadata {
    name      = "stockops-spring-service"
    namespace = "default"
  }
  spec {
    selector = { app = "stockops-spring" }
    port {
      port        = 8080
      target_port = 8080 # 🌟 컨테이너 내부 8080 포트로 정상 포워딩합니다.
      protocol    = "TCP"
    }
    type = "ClusterIP"
  }
}

resource "kubernetes_manifest" "spring_tgb" {
  manifest = {
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata = {
      name      = "stockops-spring-tgb"
      namespace = "default"
    }
    spec = {
      serviceRef = {
        name = kubernetes_service_v1.stockops_spring_svc.metadata[0].name
        port = 8080
      }
      targetGroupARN = module.seoul_alb.spring_tg_arn
    }
  }
  depends_on = [helm_release.aws_lb_controller]
}

# ==========================================
# 5. 인프라 테스트용 AI 분석 백엔드 (FastAPI 포트 8000 - 우회 유지)
# ==========================================
# seoul/kubernetes.tf 파일 내부의 5번 FastAPI 리소스 양식

resource "kubernetes_deployment_v1" "stockops_fastapi" {
  metadata {
    name      = "stockops-fastapi-backend"
    namespace = "default"
    labels    = { app = "stockops-fastapi" }
  }

  spec {
    replicas = 2
    selector { match_labels = { app = "stockops-fastapi" } }

    template {
      metadata { labels = { app = "stockops-fastapi" } }
      spec {
        container {
          name  = "fastapi-container"
          # 🌟 [확인] 이 주소가 nginx:alpine이 아니라 아래 ECR 주소여야 합니다!
          image = "247385839803.dkr.ecr.ap-northeast-2.amazonaws.com/seoul-stockops-app-repo:ai"
          
          image_pull_policy = "Always"
          port { container_port = 8000 }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "stockops_fastapi_svc" {
  metadata {
    name      = "stockops-fastapi-service"
    namespace = "default"
  }
  spec {
    selector = { app = "stockops-fastapi" }
    port {
      port        = 8000
      target_port = 8000
      protocol    = "TCP"
    }
    type = "ClusterIP"
  }
}

resource "kubernetes_manifest" "fastapi_tgb" {
  manifest = {
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata = {
      name      = "stockops-fastapi-tgb"
      namespace = "default"
    }
    spec = {
      serviceRef = {
        name = kubernetes_service_v1.stockops_fastapi_svc.metadata[0].name
        port = 8000
      }
      targetGroupARN = module.seoul_alb.fastapi_tg_arn
    }
  }
  depends_on = [helm_release.aws_lb_controller]
}

# ==========================================
# 6. 인프라 테스트용 프론트엔드 (React Mock 포트 80 - ECR 실제 이미지 연동)
# ==========================================
resource "kubernetes_deployment_v1" "stockops_frontend" {
  metadata {
    name      = "stockops-frontend"
    namespace = "default"
    labels    = { app = "stockops-frontend" }
  }

  spec {
    replicas = 2
    selector { match_labels = { app = "stockops-frontend" } }

    template {
      metadata { labels = { app = "stockops-frontend" } }
      spec {
        container {
          name  = "frontend-container"
          # 🌟 [ECR 이미지 연동] 방금 푸시하신 프론트엔드 실제 이미지 주소로 교체합니다.
          image = "247385839803.dkr.ecr.ap-northeast-2.amazonaws.com/seoul-stockops-app-repo:frontend"
          port { container_port = 80 }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "stockops_frontend_svc" {
  metadata {
    name      = "stockops-frontend-service"
    namespace = "default"
  }
  spec {
    selector = { app = "stockops-frontend" }
    port {
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }
    type = "ClusterIP"
  }
}

resource "kubernetes_manifest" "frontend_snapshot_tgb" {
  manifest = {
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata = {
      name      = "stockops-frontend-tgb"
      namespace = "default"
    }
    spec = {
      serviceRef = {
        name = kubernetes_service_v1.stockops_frontend_svc.metadata[0].name
        port = 80
      }
      targetGroupARN = module.seoul_alb.frontend_tg_arn
    }
  }
  depends_on = [helm_release.aws_lb_controller]
}