# ==========================================================================
# VPC 모듈 — 입력 변수
# ==========================================================================

variable "region_name" {
  description = "리전 식별자 (예: seoul, ohio)"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR 블록 (예: 10.0.0.0/16)"
  type        = string
}

variable "az_a" {
  description = "가용 영역 A (예: ap-northeast-2a)"
  type        = string
}

variable "az_c" {
  description = "가용 영역 C (예: ap-northeast-2c)"
  type        = string
}

variable "pub_sub_2a_cidr" {
  description = "퍼블릭 서브넷 AZ-a CIDR"
  type        = string
}

variable "pub_sub_2c_cidr" {
  description = "퍼블릭 서브넷 AZ-c CIDR"
  type        = string
}

variable "priv_app_sub_2a_cidr" {
  description = "프라이빗 앱 서브넷 AZ-a CIDR"
  type        = string
}

variable "priv_app_sub_2c_cidr" {
  description = "프라이빗 앱 서브넷 AZ-c CIDR"
  type        = string
}

variable "priv_db_sub_2a_cidr" {
  description = "프라이빗 DB 서브넷 AZ-a CIDR"
  type        = string
}

variable "priv_db_sub_2c_cidr" {
  description = "프라이빗 DB 서브넷 AZ-c CIDR"
  type        = string
}
