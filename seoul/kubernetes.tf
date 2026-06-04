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

# --------------------------------------------------------------------------
# [컴포넌트 1] stockops-client-web (사용자 포털 - Port 80)
# --------------------------------------------------------------------------
resource "kubernetes_deployment_v1" "client_web" {
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
          image             = "247385839803.dkr.ecr.ap-northeast-2.amazonaws.com/stockops-client-web:latest"
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
          image             = "247385839803.dkr.ecr.ap-northeast-2.amazonaws.com/stockops-admin-web:latest"
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
          image             = "247385839803.dkr.ecr.ap-northeast-2.amazonaws.com/stockops-api:latest"
          readiness_probe {
            http_get {
              path = "/api/health" # 혹은 실제 존재하는 헬스체크 경로
              port = 8080
            }
            initial_delay_seconds = 60 # 60초간 대기
            period_seconds        = 10
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
          image             = "247385839803.dkr.ecr.ap-northeast-2.amazonaws.com/stockops-ai:latest"
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

# ==========================================================================
# 상용 4대 컴포넌트 전용 AWS TargetGroupBinding 매핑 연동 (대소문자 규격 교정본)
# ==========================================================================

resource "kubernetes_manifest" "client_tgb" {
  manifest = {
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata = {
      name      = "stockops-client-tgb"
      namespace = kubernetes_namespace_v1.stockops.metadata[0].name
    }
    spec = {
      serviceRef = {
        name = kubernetes_service_v1.client_web_svc.metadata[0].name
        port = 80
      }
      # 🌟 [스키마 충돌 해결] targetGroupArn 을 targetGroupARN (대문자)으로 전면 수정합니다.
      targetGroupARN = module.seoul_alb.frontend_tg_arn
    }
  }
}

resource "kubernetes_manifest" "admin_tgb" {
  manifest = {
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata = {
      name      = "stockops-admin-tgb"
      namespace = kubernetes_namespace_v1.stockops.metadata[0].name
    }
    spec = {
      serviceRef = {
        name = kubernetes_service_v1.admin_web_svc.metadata[0].name
        port = 80
      }
      # 🌟 [스키마 충돌 해결] targetGroupARN 대문자 적용
      targetGroupARN = module.seoul_alb.admin_tg_arn
    }
  }
}

resource "kubernetes_manifest" "api_tgb" {
  manifest = {
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata = {
      name      = "stockops-api-tgb"
      namespace = kubernetes_namespace_v1.stockops.metadata[0].name
    }
    spec = {
      serviceRef = {
        name = kubernetes_service_v1.api_server_svc.metadata[0].name
        port = 8080
      }
      # 🌟 [스키마 충돌 해결] targetGroupARN 대문자 적용
      targetGroupARN = module.seoul_alb.spring_tg_arn
    }
  }
}

resource "kubernetes_manifest" "ai_tgb" {
  manifest = {
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata = {
      name      = "stockops-ai-tgb"
      namespace = kubernetes_namespace_v1.stockops.metadata[0].name
    }
    spec = {
      serviceRef = {
        name = kubernetes_service_v1.ai_module_svc.metadata[0].name
        port = 8000
      }
      # 🌟 [스키마 충돌 해결] targetGroupARN 대문자 적용
      targetGroupARN = module.seoul_alb.fastapi_tg_arn
    }
  }
}