# ==========================================================================
# EKS 모듈 — 입력 변수
# ==========================================================================

variable "region_name" {
  description = "리전 식별자 (예: seoul, ohio)"
  type        = string
}

variable "vpc_id" {
  description = "EKS 클러스터가 속할 VPC ID"
  type        = string
}

variable "priv_app_subnet_ids" {
  description = "EKS 워커 노드를 배치할 프라이빗 앱 서브넷 ID 목록"
  type        = list(string)
}

variable "app_sg_id" {
  description = "ALB 트래픽을 수신할 앱 보안 그룹 ID"
  type        = string
}

variable "db_sg_id" {
  description = "EKS 노드의 접근을 허용할 DB 보안 그룹 ID"
  type        = string
}

variable "spring_tg_arn" {
  description = "api-server ALB 타겟 그룹 ARN"
  type        = string
}

variable "fastapi_tg_arn" {
  description = "ai-module ALB 타겟 그룹 ARN"
  type        = string
}

variable "node_desired" {
  type    = number
  default = 1
}

variable "node_min" {
  type    = number
  default = 1
}

variable "node_max" {
  type    = number
  default = 4
}