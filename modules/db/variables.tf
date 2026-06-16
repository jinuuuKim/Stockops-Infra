# ==========================================================================
# DB 모듈 — 입력 변수
# ==========================================================================

variable "region_name" {
  description = "리전 식별자 (예: seoul, ohio)"
  type        = string
}

variable "priv_db_subnet_ids" {
  description = "RDS를 배치할 프라이빗 DB 서브넷 ID 목록"
  type        = list(string)
}

variable "db_sg_id" {
  description = "RDS에 적용할 DB 전용 보안 그룹 ID"
  type        = string
}

variable "db_username" {
  description = "PostgreSQL 마스터 사용자 이름"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "RDS PostgreSQL 마스터 비밀번호"
  type        = string
  sensitive   = true
}