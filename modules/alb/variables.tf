# ==========================================================================
# ALB 모듈 — 입력 변수
# ==========================================================================

variable "region_name" {
  description = "리전 식별자 (예: seoul, ohio)"
  type        = string
}

variable "vpc_id" {
  description = "ALB를 배치할 VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "ALB를 배치할 퍼블릭 서브넷 ID 목록"
  type        = list(string)
}

variable "acm_certificate_arn" {
  description = "HTTPS 리스너용 ACM 인증서 ARN"
  type        = string
  default     = ""
}

variable "domain" {
  type    = string
  default = "siseon.live"
}