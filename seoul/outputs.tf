# ==========================================================================
# 최종 결과값 터미널 화면 출력 (Outputs)
# ==========================================================================

output "seoul_alb_dns" {
  description = "프로젝트 서울 리전 메인 웹 진입 주소"
  value       = module.seoul_alb.alb_dns_name
}

output "seoul_database_host" {
  description = "RDS 접속 엔드포인트 주소"
  value       = module.seoul_db.db_address
}

output "stockops_ecr_urls" {
  description = "MSA 4대 컴포넌트 전용 ECR 저장소 URL 전체 목록"
  value       = { for k, v in module.seoul_ecr : k => v.repository_url }
}

output "github_actions_role_arn" {
  value = module.github_oidc.role_arn
}

output "certificate_pem" {
  value     = module.seoul_iot.certificate_pem
  sensitive = true
}

output "private_key" {
  value     = module.seoul_iot.private_key
  sensitive = true
}