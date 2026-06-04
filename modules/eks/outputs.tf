output "cluster_name" {
  value       = aws_eks_cluster.this.name
  description = "EKS 클러스터 고유 식별 명칭"
}

output "cluster_endpoint" {
  value       = aws_eks_cluster.this.endpoint
  description = "쿠버네티스 컨트롤 플레인 API 서버 접속 주소"
}

output "cluster_ca_certificate" {
  value       = aws_eks_cluster.this.certificate_authority[0].data
  description = "보안 인증을 위한 CA 공개키 데이터"
}

output "oidc_issuer" {
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
  description = "쿠버네티스 서비스 어카운트 IAM 자격 증명 연동을 위한 OIDC 주소"
}

output "cluster_security_group_id" {
  description = "EKS 클러스터가 자동 생성하여 노드들에 채워준 진짜 보안 그룹 ID"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "lbc_role_arn" {
  value = aws_iam_role.lbc.arn
}

output "lbc_role_policy_attachment" {
  value = aws_iam_role_policy_attachment.lbc.id
}