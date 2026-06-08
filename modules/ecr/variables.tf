# ==========================================================================
# ECR 모듈 — 입력 변수
# ==========================================================================

variable "region_name" {
  description = "리전 식별자 (예: seoul, ohio)"
  type        = string
}

variable "repository_name" {
  description = "생성할 ECR 리포지토리 이름 (예: stockops-api)"
  type        = string
}
