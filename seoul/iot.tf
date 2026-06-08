# ==========================================================================
# 서울 리전 — IoT Core 파이프라인
# 흐름: 온프레미스 센서 → Mosquitto 브리지 → IoT Core → SQS → 백엔드
# ==========================================================================

module "seoul_iot" {
  source = "../modules/iot"

  thing_name     = "mosquitto-bridge"
  topic_prefix   = "sensimul/sites"
  sqs_queue_name = "stockops-sensor-data"
  sqs_dlq_name   = "stockops-sensor-data-dlq"
}
