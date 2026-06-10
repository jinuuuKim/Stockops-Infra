# ==========================================================================
# Karpenter 모듈 — 출력 변수
# ==========================================================================

output "karpenter_role_arn" {
  description = "Karpenter IAM Role ARN"
  value       = aws_iam_role.karpenter.arn
}

output "node_role_name" {
  description = "Karpenter가 사용할 노드 IAM Role 이름"
  value       = split("/", var.node_role_arn)[1]
}