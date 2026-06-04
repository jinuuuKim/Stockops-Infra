# ==========================================================================
# ECR 모듈 - 입력 변수 정의 (Variables)
# ==========================================================================

variable "region_name" {
  description = "행정 구역 및 리전 이름 (예: seoul, tokyo)"
  type        = string
}

# 🌟 [에러 해결 핵심] 저장소 이름을 외부에서 동적으로 수령할 변수를 선언합니다.
variable "repository_name" {
  description = "생성할 ECR 저장소의 고유 명칭"
  type        = string
}