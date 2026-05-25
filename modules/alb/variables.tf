# ==========================================================================
# ALB 모듈 - 입력 변수 정의 (Variables)
# ==========================================================================

variable "region_name" {
  description = "리전 식별자 이름 (seoul, tokyo)"
  type        = string
}

variable "vpc_id" {
  description = "ALB가 연결될 VPC ID (VPC 모듈의 출력값 연동)"
  type        = string
}

variable "public_subnet_ids" {
  description = "ALB를 배치할 외부 개방형 퍼블릭 서브넷 ID 리스트"
  type        = list(string)
}