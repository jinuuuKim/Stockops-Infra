# ==========================================================================
# 서울 EKS 클러스터 - 상용 애플리케이션 및 인프라 컴포넌트 배치 명세서 (문법 교정판)
# ==========================================================================

# 1. 실서비스 전용 독립 네임스페이스 개설
resource "kubernetes_namespace_v1" "stockops" {
  metadata {
    name = "stockops"
  }
}

# 2. External Secrets Operator (ESO) 보안 컨트롤러 자동 배포
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

# --------------------------------------------------------------------------
# [컴포넌트 1] stockops-client-web (사용자 포털 - Port 80)
# --------------------------------------------------------------------------
resource "kubernetes_deployment_v1" "client_web" {
  wait_for_rollout = false
  metadata {
    name      = "stockops-client-web"
    namespace = kubernetes_namespace_v1.stockops.metadata[0].name
    labels    = { app = "stockops-client-web" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "stockops-client-web" } }
    template {
      metadata { labels = { app = "stockops-client-web" } }
      spec {
        container {
          name              = "client-web-container"
          image = "${module.seoul_ecr["stockops-client-web"].repository_url}:latest"
          image_pull_policy = "Always"
          port { container_port = 80 }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "client_web_svc" {
  metadata {
    name      = "stockops-client-web-svc"
    namespace = kubernetes_namespace_v1.stockops.metadata[0].name
  }
  spec {
    selector = { app = "stockops-client-web" }
    # 🌟 [문법 교정] 테라폼 정석 규칙에 맞추어 줄바꿈(개행) 형태로 분리했습니다.
    port {
      port        = 80
      target_port = 80
    }
    type = "ClusterIP"
  }
}

# --------------------------------------------------------------------------
# [컴포넌트 2] stockops-admin-web (관리자 웹 - Port 80)
# --------------------------------------------------------------------------
resource "kubernetes_deployment_v1" "admin_web" {
  wait_for_rollout = false
  metadata {
    name      = "stockops-admin-web"
    namespace = kubernetes_namespace_v1.stockops.metadata[0].name
    labels    = { app = "stockops-admin-web" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "stockops-admin-web" } }
    template {
      metadata { labels = { app = "stockops-admin-web" } }
      spec {
        container {
          name              = "admin-web-container"
          image = "${module.seoul_ecr["stockops-admin-web"].repository_url}:latest"
          image_pull_policy = "Always"
          port { container_port = 80 }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "admin_web_svc" {
  metadata {
    name      = "stockops-admin-web-svc"
    namespace = kubernetes_namespace_v1.stockops.metadata[0].name
  }
  spec {
    selector = { app = "stockops-admin-web" }
    # 🌟 [문법 교정] 줄바꿈 형태로 정렬 완료
    port {
      port        = 80
      target_port = 80
    }
    type = "ClusterIP"
  }
}

# --------------------------------------------------------------------------
# [컴포넌트 3] stockops-api-server (메인 Spring 백엔드 - Port 8080)
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
          image = "${module.seoul_ecr["stockops-api"].repository_url}:latest"
          
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
            name  = "MANAGEMENT_ENDPOINT_HEALTH_SHOW_DETAILS"
            value = "always"
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
            name  = "SPRING_PROFILES_ACTIVE"
            value = "dev"
          }
          env {
            name  = "STOCKOPS_DATASOURCE_URL"
            value = "jdbc:postgresql://${module.seoul_db.db_address}:5432/stockops"
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
            name  = "SPRING_MAIL_HOST"
            value = "smtp.gmail.com"  # 또는 사용하는 SMTP 서버
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
          image_pull_policy = "Always"
          port { container_port = 8080 }
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
    # 🌟 [문법 교정] 줄바꿈 형태로 정렬 완료
    port {
      port        = 8080
      target_port = 8080
    }
    type = "ClusterIP"
  }
}

# --------------------------------------------------------------------------
# [컴포넌트 4] stockops-ai-module (FastAPI AI 분석 - Port 8000)
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
          image = "${module.seoul_ecr["stockops-ai"].repository_url}:latest"
          image_pull_policy = "Always"
          port { container_port = 8000 }
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
    # 🌟 [문법 교정] 줄바꿈 형태로 정렬 완료
    port {
      port        = 8000
      target_port = 8000
    }
    type = "ClusterIP"
  }
}

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
        }
      }
    }
  }
}

### REDIS
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

# ==========================================================================
# 상용 4대 컴포넌트 전용 AWS TargetGroupBinding 매핑 연동 (대소문자 규격 교정본)
# ==========================================================================

resource "kubectl_manifest" "client_tgb" {
  yaml_body = yamlencode({
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata   = { name = "stockops-client-tgb", namespace = kubernetes_namespace_v1.stockops.metadata[0].name }
    spec = {
      targetType     = "ip"
      serviceRef     = { name = kubernetes_service_v1.client_web_svc.metadata[0].name, port = 80 }
      targetGroupARN = module.seoul_alb.frontend_tg_arn
    }
  })
  depends_on = [helm_release.aws_load_balancer_controller]
}

resource "kubectl_manifest" "admin_tgb" {
  yaml_body = yamlencode({
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata   = { name = "stockops-admin-tgb", namespace = kubernetes_namespace_v1.stockops.metadata[0].name }
    spec = {
      targetType     = "ip"
      serviceRef     = { name = kubernetes_service_v1.admin_web_svc.metadata[0].name, port = 80 }
      targetGroupARN = module.seoul_alb.admin_tg_arn
    }
  })
  depends_on = [helm_release.aws_load_balancer_controller]
}

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