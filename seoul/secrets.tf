# ==========================================================================
# Secrets Manager + ESO IRSA
# ==========================================================================

# 1. Secrets Manager 시크릿 생성
resource "aws_secretsmanager_secret" "stockops" {
  name                    = "stockops/app"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "stockops" {
  secret_id = aws_secretsmanager_secret.stockops.id
  secret_string = jsonencode({
    JWT_SECRET  = var.jwt_secret
    DB_USERNAME = var.db_username
    DB_PASSWORD = var.db_password
    })
}

# 2. ESO용 IRSA
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
      Effect   = "Allow"
      Action   = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = aws_secretsmanager_secret.stockops.arn
    }]
  })
}