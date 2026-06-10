# ==========================================================================
# Karpenter 모듈 — 입력 변수
# ==========================================================================

variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS API 서버 엔드포인트"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC Provider ARN"
  type        = string
}

variable "oidc_provider" {
  description = "OIDC Provider URL (https:// 제거)"
  type        = string
}

variable "region_name" {
  description = "리전 이름 (리소스 네이밍용)"
  type        = string
}

variable "node_role_arn" {
  description = "EKS 워커 노드 IAM Role ARN"
  type        = string
}

variable "karpenter_replicas" {
  description = "Karpenter 파드 replica 수"
  type        = number
  default     = 2
}