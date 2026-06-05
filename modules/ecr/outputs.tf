# ==========================================================================
# ECR 모듈 - 출력 변수 정의 (Outputs)
# ==========================================================================

output "repository_url" {
  value       = aws_ecr_repository.app_repo.repository_url
  description = "애플리케이션 도커 이미지를 푸시할 ECR 주소"
}

output "repository_arn" {
  value       = aws_ecr_repository.app_repo.arn
  description = "IAM 정책에서 ECR push 권한 범위 지정에 사용하는 ARN"
}