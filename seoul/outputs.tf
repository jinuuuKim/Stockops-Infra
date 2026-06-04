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

output "stockops_app_ecr_url" {
  description = "Gitea 소스 코드를 빌드하여 푸시할 AWS ECR 프라이빗 저장소 주소"
  value       = module.seoul_ecr.repository_url
}