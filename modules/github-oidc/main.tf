# ==========================================================================
# GitHub OIDC 모듈 — GitHub Actions → AWS IAM Role (액세스 키 없는 인증)
# OIDC Provider는 계정당 1개. 추가 워크로드는 Role/Condition만 추가.
# ==========================================================================

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

# GitHub OIDC Identity Provider
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]

  tags = {
    Name      = "github-oidc-provider"
    ManagedBy = "terraform"
  }
}

# Trust Policy (허용 브랜치만 AssumeRole 가능)
data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        for b in var.allowed_branches :
        "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${b}"
      ]
    }
  }
}

# IAM Role
resource "aws_iam_role" "github_actions" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.github_trust.json

  tags = {
    Name      = var.role_name
    ManagedBy = "terraform"
    Purpose   = "github-actions-ci"
  }
}

# ECR Push 권한
data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = var.ecr_arns
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.ecr_push.json
}

# EKS DescribeCluster 권한 (kubectl rollout restart용)
data "aws_iam_policy_document" "eks_deploy" {
  statement {
    sid       = "EKSDescribe"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "eks_deploy" {
  name   = "eks-deploy-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.eks_deploy.json
}

# S3 정적 배포 권한 (프론트 s3 sync --delete)
data "aws_iam_policy_document" "s3_deploy" {
  statement {
    sid       = "S3ListFrontendBuckets"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [for b in var.frontend_bucket_names : "arn:aws:s3:::${b}"]
  }
  statement {
    sid    = "S3WriteFrontendObjects"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetObject",
    ]
    resources = [for b in var.frontend_bucket_names : "arn:aws:s3:::${b}/*"]
  }
}

resource "aws_iam_role_policy" "s3_deploy" {
  name   = "s3-frontend-deploy-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.s3_deploy.json
}

# CloudFront 캐시 무효화 권한
data "aws_iam_policy_document" "cloudfront_invalidate" {
  statement {
    sid    = "CloudFrontInvalidate"
    effect = "Allow"
    actions = [
      "cloudfront:ListDistributions",
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cloudfront_invalidate" {
  name   = "cloudfront-invalidate-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.cloudfront_invalidate.json
}