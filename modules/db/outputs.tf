# ==========================================================================
# DB 모듈 — 출력 변수
# ==========================================================================

output "db_endpoint" {
  description = "RDS 접속 주소 (host:port 형태)"
  value       = aws_db_instance.this.endpoint
}

output "db_address" {
  description = "RDS 호스트 주소 (앱 datasource URL 주입용)"
  value       = aws_db_instance.this.address
}
