# ==========================================================================
# VPC 모듈 - 입력 변수 정의 (Variables)
# ==========================================================================

variable "region_name" {
  description = "리전 식별자 이름 (예: seoul, tokyo)"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC의 메인 사설 IP 대역 (예: 10.0.0.0/16)"
  type        = string
}

# --- 가용 영역 (Availability Zones) ---
variable "az_a" {
  description = "해당 리전의 가용영역 A (예: ap-northeast-2a)"
  type        = string
}

variable "az_c" {
  description = "해당 리전의 가용영역 C (예: ap-northeast-2c)"
  type        = string
}

# --- 서브넷 CIDR 대역 정의 ---
variable "pub_sub_2a_cidr" {
  type = string
}

variable "pub_sub_2c_cidr" {
  type = string
}

variable "priv_app_sub_2a_cidr" {
  type = string
}

variable "priv_app_sub_2c_cidr" {
  type = string
}

variable "priv_db_sub_2a_cidr" {
  type = string
}

variable "priv_db_sub_2c_cidr" {
  type = string
}