output "role_arn" {
  description = "GitHub Actions에서 role-to-assume에 넣을 IAM Role ARN"
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  description = "생성된 GitHub OIDC Provider ARN (ArgoCD 등 추후 재사용 시 참조)"
  value       = aws_iam_openid_connect_provider.github.arn
}
