# ==========================================================================
# 서울 리전 — 입력 변수 정의
# 실제 값은 terraform.tfvars에 작성, .gitignore로 Git 비추적
# ==========================================================================

variable "domain" {
  type    = string
  default = "siseon.live"
}

variable "delegation_set_id" {
  type    = string
  default = "N02295603ILJ5HVTJBLTY"
}
