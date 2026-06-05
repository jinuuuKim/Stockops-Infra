variable "thing_name" {
  type        = string
  description = "IoT Thing 이름 (Mosquitto 브리지 client_id와 일치해야 함)"
  default     = "mosquitto-bridge"
}

variable "topic_prefix" {
  type        = string
  description = "센시뮬 토픽 prefix"
  default     = "sensimul/sites"
}

variable "sqs_queue_name" {
  type        = string
  description = "센서 데이터를 수신할 SQS 큐 이름"
  default     = "stockops-sensor-data"
}

variable "sqs_dlq_name" {
  type        = string
  description = "Dead Letter Queue 이름"
  default     = "stockops-sensor-data-dlq"
}

variable "dlq_max_receive_count" {
  type        = number
  description = "DLQ로 이동하기 전 최대 수신 시도 횟수"
  default     = 3
}
