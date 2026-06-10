# ==========================================================================
# 글로벌 리소스 — 출력 변수
# ==========================================================================

output "global_accelerator_dns" {
  description = "Global Accelerator DNS 주소 (최종 사용자 접속 진입점)"
  value       = aws_globalaccelerator_accelerator.stockops.dns_name
}

output "global_accelerator_ips" {
  description = "Global Accelerator 고정 IP 주소 목록"
  value       = aws_globalaccelerator_accelerator.stockops.ip_sets[0].ip_addresses
}
