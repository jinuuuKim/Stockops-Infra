# ==========================================================================
# VPC 모듈 - 출력 변수 정의 (Outputs)
# ==========================================================================

output "vpc_id" {
  description = "생성된 VPC의 고유 ID"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 리스트 (ALB 바인딩용)"
  value       = [aws_subnet.pub_sub_2a.id, aws_subnet.pub_sub_2c.id]
}

output "priv_app_subnet_ids" {
  description = "프라이빗 애플리케이션 서브넷 ID 리스트 (ECS Fargate 배치용)"
  value       = [aws_subnet.priv_app_sub_2a.id, aws_subnet.priv_app_sub_2c.id]
}

output "priv_db_subnet_ids" {
  description = "프라이빗 데이터베이스 서브넷 ID 리스트 (RDS PostgreSQL 그룹용)"
  value       = [aws_subnet.priv_db_sub_2a.id, aws_subnet.priv_db_sub_2c.id]
}