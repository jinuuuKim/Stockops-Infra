# ==========================================================================
# 오하이오 리전 — 입력 변수
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

variable "seoul_db_identifier" {
  description = "Read Replica 소스인 서울 RDS 인스턴스 식별자"
  type        = string
  default     = "seoul-rds-postgres"
}

variable "domain" {
  type    = string
  default = "siseon.live"
}