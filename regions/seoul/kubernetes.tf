# ==========================================================================
# 서울 리전 — Kubernetes 리소스 정의
# ==========================================================================

# stockops 전용 네임스페이스
resource "kubernetes_namespace_v1" "stockops" {
  metadata {
    name = "stockops"
  }
}

# Metrics Server (HPA 메트릭 수집용)
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }

  depends_on = [module.seoul_eks]
}

# External Secrets Operator (ESO)
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }
}

# AWS Load Balancer Controller
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = "seoul-cluster"
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
    value = module.seoul_eks.lbc_role_arn
  }

  depends_on = [module.seoul_eks]
}

# ArgoCD
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.7.0"

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "aws eks update-kubeconfig --region ap-northeast-2 --name seoul-cluster --profile siseon && kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io --ignore-not-found"
  }
}

# aws-auth ConfigMap — EKS 노드 Role + GitHub Actions Role 등록
resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }
  data = {
    mapRoles = yamlencode([
      {
        rolearn  = "arn:aws:iam::448768137813:role/seoul-eks-node-role"
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
      {
        rolearn  = module.github_oidc.role_arn
        username = "github-actions"
        groups   = ["system:masters"]
      },
      {
        rolearn  = "arn:aws:iam::448768137813:role/${module.seoul_karpenter.node_role_name}"
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
      # 팀원 SSO 권한셋 (jw.kim, hs.lee 등 4명 공통) — kubectl/ArgoCD 작업용
      {
        rolearn  = "arn:aws:iam::448768137813:role/aws-reserved/sso.amazonaws.com/ap-northeast-2/AWSReservedSSO_AdministratorAccess_1f4973541f6585d7"
        username = "sso-user:{{SessionName}}"
        groups   = ["system:masters"]
      }
    ])
  }
  force      = true
  depends_on = [module.seoul_eks]
}

# --------------------------------------------------------------------------
# api-server (Spring Boot 백엔드, Port 8080)
# --------------------------------------------------------------------------

resource "kubernetes_service_v1" "api_server_svc" {
  metadata {
    name      = "stockops-api-svc"
    namespace = kubernetes_namespace_v1.stockops.metadata[0].name
    labels    = { app = "stockops-api" }
  }
  spec {
    selector = { app = "stockops-api" }
    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }
    type = "ClusterIP"
  }
}

resource "kubernetes_service_account_v1" "api" {
  metadata {
    name      = "stockops-api-sa"
    namespace = kubernetes_namespace_v1.stockops.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.api_sqs.arn
    }
  }
}

# --------------------------------------------------------------------------
# ai-module (FastAPI AI 분석, Port 8000)
# --------------------------------------------------------------------------

resource "kubernetes_service_v1" "ai_module_svc" {
  metadata {
    name      = "stockops-ai-svc"
    namespace = kubernetes_namespace_v1.stockops.metadata[0].name
    labels    = { app = "stockops-ai" }
  }
  spec {
    selector = { app = "stockops-ai" }
    port {
      name        = "http"
      port        = 8000
      target_port = 8000
    }
    type = "ClusterIP"
  }
}

# --------------------------------------------------------------------------
# Redis (세션 캐시, Port 6379)
# --------------------------------------------------------------------------

resource "kubernetes_deployment_v1" "redis" {
  metadata {
    name      = "stockops-redis"
    namespace = kubernetes_namespace_v1.stockops.metadata[0].name
    labels    = { app = "stockops-redis" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "stockops-redis" } }
    template {
      metadata { labels = { app = "stockops-redis" } }
      spec {
        container {
          name  = "redis"
          image = "redis:7-alpine"
          port { container_port = 6379 }
          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "redis_svc" {
  metadata {
    name      = "stockops-redis-svc"
    namespace = kubernetes_namespace_v1.stockops.metadata[0].name
  }
  spec {
    selector = { app = "stockops-redis" }
    port {
      port        = 6379
      target_port = 6379
    }
    type = "ClusterIP"
  }
}

# --------------------------------------------------------------------------
# TargetGroupBinding — ALB Target Group ↔ K8s Service 연결
# targetType: ip 은 immutable, 변경 시 삭제 후 재생성 필요
# --------------------------------------------------------------------------

resource "kubectl_manifest" "api_tgb" {
  yaml_body = yamlencode({
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata   = { name = "stockops-api-tgb", namespace = kubernetes_namespace_v1.stockops.metadata[0].name }
    spec = {
      targetType     = "ip"
      serviceRef     = { name = kubernetes_service_v1.api_server_svc.metadata[0].name, port = 8080 }
      targetGroupARN = module.seoul_alb.spring_tg_arn
    }
  })
  depends_on = [helm_release.aws_load_balancer_controller]
}

resource "kubectl_manifest" "ai_tgb" {
  yaml_body = yamlencode({
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata   = { name = "stockops-ai-tgb", namespace = kubernetes_namespace_v1.stockops.metadata[0].name }
    spec = {
      targetType     = "ip"
      serviceRef     = { name = kubernetes_service_v1.ai_module_svc.metadata[0].name, port = 8000 }
      targetGroupARN = module.seoul_alb.fastapi_tg_arn
    }
  })
  depends_on = [helm_release.aws_load_balancer_controller]
}

# --------------------------------------------------------------------------
# ESO ClusterSecretStore + ExternalSecret
# Secrets Manager(stockops/app) → K8s Secret(stockops-secret) 자동 동기화
# --------------------------------------------------------------------------

resource "kubectl_manifest" "secret_store" {
  wait = true
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "stockops-secret-store"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = "ap-northeast-2"
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  })
  depends_on = [helm_release.external_secrets]
}

resource "kubectl_manifest" "external_secret" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "stockops-external-secret"
      namespace = kubernetes_namespace_v1.stockops.metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "stockops-secret-store"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "stockops-secret"
        creationPolicy = "Owner"
      }
      dataFrom = [{
        extract = { key = "stockops/app" }
      }]
    }
  })
  depends_on = [kubectl_manifest.secret_store]
}

# ESO ServiceAccount에 IRSA Role ARN 어노테이션 주입
resource "kubernetes_annotations" "eso_sa" {
  api_version = "v1"
  kind        = "ServiceAccount"
  metadata {
    name      = "external-secrets"
    namespace = "external-secrets"
  }
  annotations = {
    "eks.amazonaws.com/role-arn" = aws_iam_role.eso.arn
  }
  depends_on = [helm_release.external_secrets]
}

# --------------------------------------------------------------------------
# HPA — api-server
# --------------------------------------------------------------------------

resource "kubernetes_horizontal_pod_autoscaler_v2" "api_hpa" {
  metadata {
    name      = "stockops-api-hpa"
    namespace = kubernetes_namespace_v1.stockops.metadata[0].name
  }
  spec {
    min_replicas = 1
    max_replicas = 4
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = "stockops-api"
    }
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 60
        }
      }
    }
  }
}

# --------------------------------------------------------------------------
# HPA — ai-module
# --------------------------------------------------------------------------

resource "kubernetes_horizontal_pod_autoscaler_v2" "ai_hpa" {
  metadata {
    name      = "stockops-ai-hpa"
    namespace = kubernetes_namespace_v1.stockops.metadata[0].name
  }
  spec {
    min_replicas = 1
    max_replicas = 4
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = "stockops-ai"
    }
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 60
        }
      }
    }
    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
}