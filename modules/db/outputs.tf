# ==========================================================================
# DB 모듈 - 출력 변수 정의 (Outputs)
# ==========================================================================

output "db_endpoint" {
  description = "데이터베이스 접속 주소 (Host:Port 주소 형태)"
  value       = aws_db_instance.this.endpoint
}

output "db_address" {
  description = "애플리케이션 Spring/FastAPI 설정 파일에 주입할 데이터베이스 순수 Host 주소"
  value       = aws_db_instance.this.address
}