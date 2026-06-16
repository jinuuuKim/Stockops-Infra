# ==========================================================================
# 서울 리전 — Kubernetes 리소스 정의
# ==========================================================================

# stockops 전용 네임스페이스
resource "kubernetes_namespace_v1" "stockops" {
  metadata {
    name = "stockops"
  }
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
  force = true
  depends_on = [module.seoul_eks]
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
        service_account_name = kubernetes_service_account_v1.api.metadata[0].name
        container {
          name              = "api-container"
          image             = "${module.seoul_ecr["stockops-api"].repository_url}:latest"
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
          env {   
            name  = "STOCKOPS_OTLP_TRACING_ENDPOINT"
            value = "http://adot-collector-opentelemetry-collector.opentelemetry:4318/v1/traces" 
          }
          env {   
            name  = "STOCKOPS_AI_SERVICE_URL"
            value = "http://stockops-ai-svc.stockops:8000"
          }
          env {
            name  = "STOCKOPS_ACTUATOR_PROMETHEUS_PUBLIC"
            value = "true"
          }
          env {
            name  = "STOCKOPS_SQS_INGESTION_ENABLED"
            value = "true"
          }
          env {
            name  = "STOCKOPS_SQS_INGESTION_QUEUE_URL"
            value = module.seoul_iot.sqs_queue_url
          }
          env {
            name  = "STOCKOPS_SQS_INGESTION_REGION"
            value = "ap-northeast-2"
          }
          # (선택) 클라우드 백엔드는 IoT Core→SQS 경로만 쓰므로 직접 MQTT 수신은 끔.
          # 안 끄면 tcp://localhost:1883 재연결 시도 로그가 계속 쌓임(파드는 안 죽음, degraded mode).
          env {
            name  = "STOCKOPS_MQTT_INGESTION_ENABLED"
            value = "false"
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
          image             = "${module.seoul_ecr["stockops-ai"].repository_url}:latest"
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
          env {   
            name  = "OTEL_EXPORTER_OTLP_ENDPOINT"
            value = "http://adot-collector-opentelemetry-collector.opentelemetry:4318"
          }
          env {
            name = "DB_USERNAME"
            value_from {
              secret_key_ref {
                name = "stockops-secret"
                key  = "DB_USERNAME"
              }
            }
          }
          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = "stockops-secret"
                key  = "DB_PASSWORD"
              }
            }
          }
          env {
            name  = "DATABASE_URL"
            value = "postgresql://$(DB_USERNAME):$(DB_PASSWORD)@seoul-rds-postgres.cnas28mgerfu.ap-northeast-2.rds.amazonaws.com:5432/stockops"
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