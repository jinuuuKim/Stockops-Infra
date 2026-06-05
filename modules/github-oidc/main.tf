# ─────────────────────────────────────────────
# GitHub Actions OIDC → AWS IAM Role
# ─────────────────────────────────────────────
# 목적: GitHub Actions가 액세스키 없이 AssumeRoleWithWebIdentity로
#       임시 STS 자격증명을 받아 ECR push를 수행하도록 합니다.
# 주의: OIDC Provider는 계정당 1개만 존재해야 합니다.
#       ArgoCD 등 추후 워크로드 추가 시 이 provider를 재사용하고
#       Role/Condition만 추가하세요.
# ─────────────────────────────────────────────

# GitHub OIDC 엔드포인트에서 thumbprint를 동적으로 계산
# (AWS가 잘 알려진 IdP 토큰 검증에 thumbprint를 더 이상 강제하지 않지만
#  Terraform 리소스 필드가 요구하므로 안전하게 채워둡니다.)
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

# ── 1. GitHub OIDC Identity Provider ─────────
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]

  tags = {
    Name    = "github-oidc-provider"
    ManagedBy = "terraform"
  }
}

# ── 2. Trust Policy ───────────────────────────
# sub 조건: repo:ORG/REPO:ref:refs/heads/BRANCH
# 이 조건에서 벗어난 모든 요청(PR, tag, 타 레포 등)은 거부됩니다.
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

# ── 3. IAM Role ───────────────────────────────
resource "aws_iam_role" "github_actions" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.github_trust.json

  tags = {
    Name      = var.role_name
    ManagedBy = "terraform"
    Purpose   = "github-actions-ci"
  }
}

# ── 4. ECR 권한 Policy ─────────────────────────
# GetAuthorizationToken: ecr-login 스텝에 필요, resource = * 필수
# 나머지: 4개 ECR 리포지토리에만 push 권한 부여
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

# ── 5. EKS 권한 Policy ─────────────────────────
# update-kubeconfig: eks:DescribeCluster 필요
# kubectl rollout restart: eks:DescribeCluster + k8s RBAC (aws-auth)
data "aws_iam_policy_document" "eks_deploy" {
  statement {
    sid     = "EKSDescribe"
    effect  = "Allow"
    actions = ["eks:DescribeCluster"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "eks_deploy" {
  name   = "eks-deploy-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.eks_deploy.json
}
