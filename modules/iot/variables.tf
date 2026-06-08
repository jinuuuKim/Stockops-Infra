# ==========================================================================
# IoT Core 모듈 — 입력 변수
# ==========================================================================

variable "thing_name" {
  description = "IoT Thing 이름 (Mosquitto 브리지 client_id와 일치해야 함)"
  type        = string
  default     = "mosquitto-bridge"
}

variable "topic_prefix" {
  description = "센시뮬 MQTT 토픽 prefix (예: sensimul/sites)"
  type        = string
  default     = "sensimul/sites"
}

variable "sqs_queue_name" {
  description = "센서 데이터를 수신할 SQS 큐 이름"
  type        = string
  default     = "stockops-sensor-data"
}

variable "sqs_dlq_name" {
  description = "Dead Letter Queue 이름"
  type        = string
  default     = "stockops-sensor-data-dlq"
}

variable "dlq_max_receive_count" {
  description = "DLQ로 이동하기 전 최대 수신 시도 횟수"
  type        = number
  default     = 3
}
