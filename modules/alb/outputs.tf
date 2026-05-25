# ==========================================================================
# ALB 모듈 - 출력 변수 정의 (Outputs)
# ==========================================================================

output "alb_dns_name" {
  description = "사용자가 외부에서 접속할 로드 밸런서의 전체 도메인 주소"
  value       = aws_lb.alb.dns_name
}

output "alb_sg_id" {
  description = "ALB 보안 그룹 ID (ECS App 보안그룹에서 소스로 참조할 때 사용)"
  value       = aws_security_group.alb_sg.id
}

output "spring_tg_arn" {
  description = "Spring 백엔드 타겟 그룹 ARN 주소"
  value       = aws_lb_target_group.spring_tg.arn
}

output "fastapi_tg_arn" {
  description = "FastAPI 백엔드 타겟 그룹 ARN 주소"
  value       = aws_lb_target_group.fastapi_tg.arn
}