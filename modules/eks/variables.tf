variable "region_name" {
  type        = string
  description = "리전 식별자 이름 (예: seoul)"
}

variable "vpc_id" {
  type        = string
  description = "EKS 클러스터가 종속될 사설 네트워크 VPC ID"
}

variable "priv_app_subnet_ids" {
  type        = list(string)
  description = "EKS 워커 노드가 안전하게 배포될 프라이빗 애플리케이션 서브넷 ID 목록"
}

variable "app_sg_id" {
  type        = string
  description = "ALB 트래픽 수용을 위한 기존 애플리케이션 보안 그룹 ID"
}

variable "db_sg_id" {
  type        = string
  description = "EKS 노드의 접근만을 직접 허용할 사설 데이터베이스 보안 그룹 ID"
}

variable "frontend_tg_arn" {
  type        = string
  description = "ALB 모듈에서 전달된 Frontend 대상 그룹의 ARN 주소"
}

variable "spring_tg_arn" {
  type        = string
  description = "ALB 모듈에서 전달된 Spring API 대상 그룹의 ARN 주소"
}

variable "fastapi_tg_arn" {
  type        = string
  description = "ALB 모듈에서 전달된 FastAPI AI 대상 그룹의 ARN 주소"
}