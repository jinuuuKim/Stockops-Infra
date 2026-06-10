# ==========================================================================
# 서울 리전 — 입력 변수 정의
# 실제 값은 terraform.tfvars에 작성, .gitignore로 Git 비추적
# ==========================================================================

variable "jwt_secret" {
  description = "Spring Boot JWT 서명 키"
  type        = string
  sensitive   = true
}

variable "db_username" {
  description = "RDS PostgreSQL 마스터 사용자 이름"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "RDS PostgreSQL 마스터 비밀번호"
  type        = string
  sensitive   = true
}

variable "domain" {
  type    = string
  default = "siseon.live"
}

variable "delegation_set_id" {
  type    = string
  default = "N02295603ILJ5HVTJBLTY"
}