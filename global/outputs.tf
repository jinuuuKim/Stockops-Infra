# ==========================================================================
# 글로벌 리소스 — 출력 변수
# ==========================================================================

output "global_accelerator_dns" {
  description = "Global Accelerator DNS 주소 (api.siseon.live 가 가리키는 곳)"
  value       = aws_globalaccelerator_accelerator.stockops.dns_name
}

output "global_accelerator_ips" {
  description = "Global Accelerator 고정 IP 주소 목록"
  value       = aws_globalaccelerator_accelerator.stockops.ip_sets[0].ip_addresses
}

# ── 프론트엔드 (CI 의 s3 sync + invalidation 에 사용) ──
output "client_bucket" {
  description = "client-web 정적 S3 버킷"
  value       = data.aws_s3_bucket.client.bucket
}

output "admin_bucket" {
  description = "admin-web 정적 S3 버킷"
  value       = data.aws_s3_bucket.admin.bucket
}

output "client_cloudfront_id" {
  description = "client CloudFront 배포 ID (invalidation 용)"
  value       = aws_cloudfront_distribution.client.id
}

output "admin_cloudfront_id" {
  description = "admin CloudFront 배포 ID (invalidation 용)"
  value       = aws_cloudfront_distribution.admin.id
}

output "client_cloudfront_domain" {
  value = aws_cloudfront_distribution.client.domain_name
}

output "admin_cloudfront_domain" {
  value = aws_cloudfront_distribution.admin.domain_name
}

output "api_endpoint" {
  description = "동적 API 진입점 (프론트 VITE_API_BASE_URL 기준)"
  value       = "api.${var.domain}"
}
