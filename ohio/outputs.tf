# ==========================================================================
# 오하이오 리전 — 출력 변수
# ==========================================================================

output "ohio_alb_dns" {
  description = "오하이오 ALB DNS 주소 (브라우저 접속 진입점)"
  value       = module.ohio_alb.alb_dns_name
}

output "ohio_alb_arn" {
  description = "오하이오 ALB ARN (Global Accelerator 엔드포인트용)"
  value       = module.ohio_alb.alb_arn
}

output "ohio_database_host" {
  description = "오하이오 RDS Read Replica 호스트 주소"
  value       = aws_db_instance.ohio_replica.address
}
