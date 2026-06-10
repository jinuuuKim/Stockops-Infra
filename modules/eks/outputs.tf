# ==========================================================================
# EKS 모듈 — 출력 변수
# ==========================================================================

output "cluster_name" {
  description = "EKS 클러스터 이름"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS API 서버 엔드포인트"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "EKS 클러스터 CA 인증서 (base64)"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "EKS 클러스터 자동 생성 보안 그룹 ID"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_issuer" {
  description = "OIDC Issuer URL"
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "OIDC Provider ARN (IRSA 신뢰 정책 참조용)"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider" {
  description = "OIDC Provider URL (https:// 제거, IRSA condition 변수용)"
  value       = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

output "lbc_role_arn" {
  description = "AWS Load Balancer Controller IAM Role ARN"
  value       = aws_iam_role.lbc.arn
}

output "lbc_role_policy_attachment" {
  description = "LBC IAM Role 정책 연결 ID"
  value       = aws_iam_role_policy_attachment.lbc.id
}

output "node_role_arn" {
  description = "EKS 워커 노드 IAM Role ARN"
  value       = aws_iam_role.node_role.arn
}