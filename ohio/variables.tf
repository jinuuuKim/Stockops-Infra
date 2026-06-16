# ==========================================================================
# 오하이오 리전 — 입력 변수
# ==========================================================================

variable "seoul_db_identifier" {
  description = "Read Replica 소스인 서울 RDS 인스턴스 식별자"
  type        = string
  default     = "seoul-rds-postgres"
}

variable "domain" {
  type    = string
  default = "siseon.live"
} 