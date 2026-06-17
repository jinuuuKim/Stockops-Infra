# ==========================================================================
# 서울 리전 — Secrets Manager + ESO IRSA
# 흐름: Secrets Manager → ESO → K8s Secret (stockops-secret) 자동 생성
# ==========================================================================

resource "aws_secretsmanager_secret" "stockops" {
  name                    = "stockops/app"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "stockops" {
  secret_id = aws_secretsmanager_secret.stockops.id
  secret_string = jsonencode({
    JWT_SECRET           = var.jwt_secret
    DB_USERNAME          = "stockops"
    DB_PASSWORD          = var.db_password
    SPRING_MAIL_PASSWORD = "admin123"

    STOCKOPS_AI_SERVICE_API_KEY = var.stockops_ai_service_api_key
    AI_MODULE_API_KEY           = var.ai_module_api_key
    GEMINI_API_KEY              = var.gemini_api_key

    AWS_ACCESS_KEY_ID     = var.aws_access_key_id
    AWS_SECRET_ACCESS_KEY = var.aws_secret_access_key

    STOCKOPS_BEDROCK_KNOWLEDGE_BASE_ID = var.bedrock_knowledge_base_id
    STOCKOPS_BEDROCK_AGENT_ID          = var.bedrock_agent_id
    STOCKOPS_BEDROCK_AGENT_ALIAS_ID    = var.bedrock_agent_alias_id
    STOCKOPS_BEDROCK_GUARDRAIL_ID      = var.bedrock_guardrail_id

    STOCKOPS_VERTEX_AI_PROJECT_ID       = var.vertex_ai_project_id
    STOCKOPS_VERTEX_AI_CREDENTIALS_JSON = var.vertex_ai_credentials_json
  })
}

# ESO가 Secrets Manager를 읽을 수 있도록 IRSA Trust Policy 정의
data "aws_iam_policy_document" "eso_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.seoul_eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.seoul_eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets"]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.seoul_eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "stockops-eso-role"
  assume_role_policy = data.aws_iam_policy_document.eso_assume.json
}

resource "aws_iam_role_policy" "eso" {
  name = "stockops-eso-policy"
  role = aws_iam_role.eso.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      Resource = aws_secretsmanager_secret.stockops.arn
    }]
  })
}
