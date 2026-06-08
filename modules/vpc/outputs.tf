# ==========================================================================
# VPC 모듈 — 출력 변수
# ==========================================================================

output "vpc_id" {
  description = "생성된 VPC ID"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록 (ALB 배치용)"
  value       = [aws_subnet.pub_sub_2a.id, aws_subnet.pub_sub_2c.id]
}

output "priv_app_subnet_ids" {
  description = "프라이빗 앱 서브넷 ID 목록 (EKS 워커 노드 배치용)"
  value       = [aws_subnet.priv_app_sub_2a.id, aws_subnet.priv_app_sub_2c.id]
}

output "priv_db_subnet_ids" {
  description = "프라이빗 DB 서브넷 ID 목록 (RDS 서브넷 그룹용)"
  value       = [aws_subnet.priv_db_sub_2a.id, aws_subnet.priv_db_sub_2c.id]
}
