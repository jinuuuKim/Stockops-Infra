# ==========================================================================
# 글로벌 리소스 — 입력 변수
# ==========================================================================

variable "domain" {
  type    = string
  default = "siseon.live"
}

variable "client_bucket_name" {
  type    = string
  default = "siseon-frontend-client"
}

variable "admin_bucket_name" {
  type    = string
  default = "siseon-frontend-admin"
}

# 기존 프론트 버킷이 실제 위치한 리전 (확인 결과: 서울)
variable "frontend_bucket_region" {
  type    = string
  default = "ap-northeast-2"
}
