# ==========================================================================
# 오하이오 리전 — Kubernetes 리소스 정의
# ==========================================================================

# stockops 전용 네임스페이스
resource "kubernetes_namespace_v1" "stockops" {
  metadata {
    name = "stockops"
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
    value = "ohio-cluster"
  }
  set {
    name  = "vpcId"
    value = module.ohio_vpc.vpc_id
  }
  set {
    name  = "region"
    value = "us-east-2"
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
    value = module.ohio_eks.lbc_role_arn
  }

  depends_on = [module.ohio_eks]
}

# aws-auth ConfigMap — EKS 노드 Role 등록
resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }
  data = {
    mapRoles = yamlencode([
      {
        rolearn  = "arn:aws:iam::448768137813:role/ohio-eks-node-role"
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
      {
        rolearn  = "arn:aws:iam::448768137813:role/${module.ohio_karpenter.node_role_name}"
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
      {
        rolearn  = "arn:aws:iam::448768137813:role/github-actions-ecr-push"
        username = "github-actions"
        groups   = ["system:masters"]
      },
    ])
  }
  force = true
  depends_on = [module.ohio_eks]
}

# --------------------------------------------------------------------------
# api-server (Spring Boot 백엔드, Port 8080)
# --------------------------------------------------------------------------

resource "kubernetes_deployment_v1" "api_server" {
  wait_for_rollout = false
  metadata {
    name      = "stockops-api"
    namespace = kubernetes_namespace_v1.stockops.metadata[0].name
    labels    = { app = "stockops-api" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "stockops-api" } }
    template {
      metadata { labels = { app = "stockops-api" } }
      spec {
        container {
          name              = "api-container"
          image             = "448768137813.dkr.ecr.us-east-2.amazonaws.com/stockops-api:latest"
          image_pull_policy = "Always"
          port { container_port = 8080 }
          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }
          env {
            name  = "SPRING_PROFILES_ACTIVE"
            value = "prod"
          }
          env {
            name  = "STOCKOPS_DATASOURCE_URL"
            value = "jdbc:postgresql://${aws_db_instance.ohio_replica.address}:5432/stockops"
          }
          env {
            name = "STOCKOPS_DATASOURCE_USERNAME"
            value_from {
              secret_key_ref {
                name = "stockops-secret"
                key  = "DB_USERNAME"
              }
            }
          }
          env {
            name = "STOCKOPS_DATASOURCE_PASSWORD"
            value_from {
              secret_key_ref {
                name = "stockops-secret"
                key  = "DB_PASSWORD"
              }
            }
          }
          env {
            name = "JWT_SECRET"
            value_from {
              secret_key_ref {
                name = "stockops-secret"
                key  = "JWT_SECRET"
              }
            }
          }
          env {
            name  = "SPRING_DATA_REDIS_HOST"
            value = "stockops-redis-svc"
          }
          env {
            name  = "SPRING_DATA_REDIS_PORT"
            value = "6379"
          }
          env {
            name  = "SPRING_MAIL_HOST"
            value = "smtp.gmail.com"
          }
          env {
            name  = "SPRING_MAIL_PORT"
            value = "587"
          }
          env {
            name  = "SPRING_MAIL_USERNAME"
            value = "admin@stockops.com"
          }
          env {
            name  = "SPRING_MAIL_PASSWORD"
            value = "admin123"
          }
          env {
            name  = "MANAGEMENT_ENDPOINT_HEALTH_SHOW_DETAILS"
            value = "always"
          }
          env {
            name  = "STOCKOPS_CORS_ALLOWED_ORIGINS"
            value = "https://app.siseon.live,https://siseon.live"
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "api_server_svc" {
  metadata {
    name      = "stockops-api-svc"
    namespace = kubernetes_namespace_v1.stockops.metadata[0].name
  }
  spec {
    selector = { app = "stockops-api" }
    port {
      port        = 8080
      target_port = 8080
    }
    type = "ClusterIP"
  }
}

# --------------------------------------------------------------------------
# ai-module (FastAPI AI 분석, Port 8000)
# --------------------------------------------------------------------------

resource "kubernetes_deployment_v1" "ai_module" {
  wait_for_rollout = false
  metadata {
    name      = "stockops-ai"
    namespace = kubernetes_namespace_v1.stockops.metadata[0].name
    labels    = { app = "stockops-ai" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "stockops-ai" } }
    template {
      metadata { labels = { app = "stockops-ai" } }
      spec {
        container {
          name              = "ai-container"
          image             = "448768137813.dkr.ecr.us-east-2.amazonaws.com/stockops-ai:latest"
          image_pull_policy = "Always"
          port { container_port = 8000 }
          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "ai_module_svc" {
  metadata {
    name      = "stockops-ai-svc"
    namespace = kubernetes_namespace_v1.stockops.metadata[0].name
  }
  spec {
    selector = { app = "stockops-ai" }
    port {
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
# --------------------------------------------------------------------------  

resource "kubectl_manifest" "api_tgb" {
  yaml_body = yamlencode({
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata   = { name = "stockops-api-tgb", namespace = kubernetes_namespace_v1.stockops.metadata[0].name }
    spec = {
      targetType     = "ip"
      serviceRef     = { name = kubernetes_service_v1.api_server_svc.metadata[0].name, port = 8080 }
      targetGroupARN = module.ohio_alb.spring_tg_arn
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
      targetGroupARN = module.ohio_alb.fastapi_tg_arn
    }
  })
  depends_on = [helm_release.aws_load_balancer_controller]
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
          region  = "us-east-2"
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
        extract = {
          key = "stockops/app"
        }
      }]
    }
  })
  depends_on = [kubectl_manifest.secret_store]
}

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