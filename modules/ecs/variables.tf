# ==========================================================================
# ECS 모듈 - 입력 변수 정의 (Variables)
# ==========================================================================

variable "region_name" {
  description = "리전 식별자 이름 (seoul, tokyo)"
  type        = string
}

variable "vpc_id" {
  description = "ECS가 종속될 VPC ID"
  type        = string
}

variable "priv_app_subnet_ids" {
  description = "ECS 컨테이너 태스크들이 안전하게 배치될 프라이빗 앱 서브넷 ID 리스트"
  type        = list(string)
}

variable "app_sg_id" {
  description = "서울 실행 폴더에서 정렬한 애플리케이션 가상 방화벽(Security Group) ID"
  type        = string
}

variable "spring_tg_arn" {
  description = "ALB 모듈에서 생성된 Spring API 타겟 그룹의 ARN 주소"
  type        = string
}

variable "fastapi_tg_arn" {
  description = "ALB 모듈에서 생성된 FastAPI AI 타겟 그룹의 ARN 주소"
  type        = string
}