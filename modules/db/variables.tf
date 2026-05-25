# ==========================================================================
# DB 모듈 - 입력 변수 정의 (Variables)
# ==========================================================================

variable "region_name" {
  description = "리전 식별자 이름 (seoul, tokyo)"
  type        = string
}

variable "priv_db_subnet_ids" {
  description = "RDS가 상주할 프라이빗 데이터베이스 서브넷 ID 리스트"
  type        = list(string)
}

variable "db_sg_id" {
  description = "seoul/security_groups.tf 에서 정의한 DB 전용 보안 그룹 ID"
  type        = string
}

# --- DB 마스터 계정 설정 (개발 편의상 변수 기본값 부여, 실무선 외부 주입 권장) ---
variable "db_username" {
  description = "PostgreSQL 마스터 사용자 이름"
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "PostgreSQL 마스터 비밀번호"
  type        = string
  default     = "StockOpsPass123!" # 대소문자 및 특수문자 조합 필수
}