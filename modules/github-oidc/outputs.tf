# ==========================================================================
# GitHub OIDC 모듈 — 출력 변수
# ==========================================================================

output "role_arn" {
  description = "GitHub Actions deploy.yml의 role-to-assume에 사용할 IAM Role ARN"
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  description = "GitHub OIDC Provider ARN (추후 ArgoCD 등 재사용 시 참조)"
  value       = aws_iam_openid_connect_provider.github.arn
}
