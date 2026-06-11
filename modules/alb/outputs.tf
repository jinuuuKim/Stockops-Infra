# ==========================================================================
# ALB 모듈 — 출력 변수
# ==========================================================================

output "alb_dns_name" {
  description = "ALB DNS 주소 (외부 접속 진입점)"
  value       = aws_lb.alb.dns_name
}

output "alb_arn" {
  description = "ALB ARN (Global Accelerator 엔드포인트용)"
  value       = aws_lb.alb.arn
}

output "alb_sg_id" {
  description = "ALB 보안 그룹 ID (EKS 노드 SG 소스 참조용)"
  value       = aws_security_group.alb_sg.id
}

output "spring_tg_arn" {
  description = "api-server (Spring Boot) 타겟 그룹 ARN"
  value       = aws_lb_target_group.spring_tg.arn
}

output "fastapi_tg_arn" {
  description = "ai-module (FastAPI) 타겟 그룹 ARN"
  value       = aws_lb_target_group.fastapi_tg.arn
}

output "alb_zone_id" {
  description = "ALB hosted zone ID (Route53 Alias 레코드용)"
  value       = aws_lb.alb.zone_id
}