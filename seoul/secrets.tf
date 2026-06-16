# ==========================================================================
# 서울 리전 — Secrets Manager + ESO IRSA
# 흐름: Secrets Manager → ESO → K8s Secret (stockops-secret) 자동 생성
# ==========================================================================

resource "random_password" "jwt" {
  length           = 64
  special          = true
  override_special = "!#%*-_=+"   # env 주입에 안전한 문자만
}

resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#%*-_=+"
}

resource "aws_secretsmanager_secret" "stockops" {
  name                    = "stockops/app"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "stockops" {
  secret_id = aws_secretsmanager_secret.stockops.id
  secret_string = jsonencode({
    JWT_SECRET  = random_password.jwt.result
    DB_USERNAME = "stockops"
    DB_PASSWORD = random_password.db.result
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
