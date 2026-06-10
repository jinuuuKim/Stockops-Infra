# ==========================================================================
# 서울 리전 — 출력 변수 정의
# ==========================================================================

output "seoul_alb_dns" {
  description = "서울 ALB DNS 주소 (브라우저 접속 진입점)"
  value       = module.seoul_alb.alb_dns_name
}

output "seoul_alb_arn" {
  description = "서울 ALB ARN (Global Accelerator 엔드포인트용)"
  value       = module.seoul_alb.alb_arn
}

output "seoul_database_host" {
  description = "RDS 접속 호스트 주소"
  value       = module.seoul_db.db_address
}

output "stockops_ecr_urls" {
  description = "MSA 4개 컴포넌트 ECR 리포지토리 URL 목록"
  value       = { for k, v in module.seoul_ecr : k => v.repository_url }
}

output "github_actions_role_arn" {
  description = "GitHub Actions OIDC IAM Role ARN"
  value       = module.github_oidc.role_arn
}

output "account_id" {
  description = "AWS 계정 ID (오하이오 모듈 등 크로스 리전 참조용)"
  value       = data.aws_caller_identity.current.account_id
}

output "sensor_sqs_queue_url" {
  description = "IoT 센서 데이터 SQS 큐 URL"
  value       = module.seoul_iot.sqs_queue_url
}
