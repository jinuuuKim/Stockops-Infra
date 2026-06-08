# ==========================================================================
# 오하이오 리전 — Secrets Manager + ESO IRSA
# ==========================================================================

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

data "aws_iam_policy_document" "eso_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.ohio_eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.ohio_eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets"]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.ohio_eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "ohio-eso-role"
  assume_role_policy = data.aws_iam_policy_document.eso_assume.json
}

resource "aws_iam_role_policy" "eso" {
  name = "ohio-eso-policy"
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