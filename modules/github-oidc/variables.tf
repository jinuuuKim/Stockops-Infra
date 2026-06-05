variable "github_org" {
  type        = string
  description = "GitHub 조직 또는 유저 이름"
  default     = "jinuuuKim"
}

variable "github_repo" {
  type        = string
  description = "GitHub 레포지토리 이름"
  default     = "Stockops-Application"
}

variable "allowed_branches" {
  type        = list(string)
  description = "ECR push를 허용할 브랜치 목록"
  default     = ["main"]
}

variable "ecr_arns" {
  type        = list(string)
  description = "push 권한을 부여할 ECR 리포지토리 ARN 목록"
}

variable "role_name" {
  type        = string
  description = "생성할 IAM Role 이름"
  default     = "github-actions-ecr-push"
}
