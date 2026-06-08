# ==========================================================================
# GitHub OIDC 모듈 — 입력 변수
# ==========================================================================

variable "github_org" {
  description = "GitHub 조직 또는 계정 이름"
  type        = string
  default     = "jinuuuKim"
}

variable "github_repo" {
  description = "GitHub 리포지토리 이름"
  type        = string
  default     = "Stockops-Application"
}

variable "allowed_branches" {
  description = "ECR push를 허용할 브랜치 목록"
  type        = list(string)
  default     = ["main"]
}

variable "ecr_arns" {
  description = "push 권한을 부여할 ECR 리포지토리 ARN 목록"
  type        = list(string)
}

variable "role_name" {
  description = "생성할 IAM Role 이름"
  type        = string
  default     = "github-actions-ecr-push"
}
