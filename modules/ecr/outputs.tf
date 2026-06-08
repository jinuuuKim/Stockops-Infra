# ==========================================================================
# ECR 모듈 — 출력 변수
# ==========================================================================

output "repository_url" {
  description = "이미지 push/pull에 사용할 ECR 리포지토리 URL"
  value       = aws_ecr_repository.app_repo.repository_url
}

output "repository_arn" {
  description = "IAM 정책 ECR push 권한 범위 지정용 ARN"
  value       = aws_ecr_repository.app_repo.arn
}
