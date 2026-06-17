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

output "priv_app_rt_id" {
  description = "프라이빗 앱 라우팅 테이블 ID (VPC 피어링 라우트 추가용)"
  value       = aws_route_table.priv_app_rt.id
}

output "priv_db_rt_id" {
  description = "프라이빗 DB 라우팅 테이블 ID (VPC 피어링 라우트 추가용)"
  value       = aws_route_table.priv_db_rt.id
}

output "pub_rt_id" {
  description = "퍼블릭 라우팅 테이블 ID (VPC 피어링 라우트 추가용)"
  value       = aws_route_table.pub_rt.id
}
