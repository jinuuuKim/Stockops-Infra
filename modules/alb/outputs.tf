# ==========================================================================
# ALB 모듈 - 출력 변수 정의 (Outputs)
# ==========================================================================

output "alb_dns_name" {
  description = "사용자가 외부에서 접속할 로드 밸런서의 전체 도메인 주소"
  value       = aws_lb.alb.dns_name # [교정] this에서 alb로 변경하여 리소스 이름과 일치시킵니다.
}

output "alb_sg_id" {
  description = "ALB 보안 그룹 ID (EKS 노드 보안그룹에서 소스로 참조할 때 사용)"
  value       = aws_security_group.alb_sg.id
}

output "frontend_tg_arn" {
  description = "정적 프론트엔드 웹 서비스 대상 그룹 ARN"
  value       = aws_lb_target_group.frontend_tg.arn
}

output "admin_tg_arn" {
  description = "관리자 대시보드(Admin Web) 대상 그룹 ARN"
  value       = aws_lb_target_group.admin_tg.arn
}

output "spring_tg_arn" {
  description = "Spring 백엔드 타겟 그룹 ARN 주소"
  value       = aws_lb_target_group.spring_tg.arn
}

output "fastapi_tg_arn" {
  description = "FastAPI 백엔드 타겟 그룹 ARN 주소"
  value       = aws_lb_target_group.fastapi_tg.arn
}