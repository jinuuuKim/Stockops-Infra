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
  iot_certificate_arn = "arn:aws:iot:ap-northeast-2:448768137813:cert/c4ac7c856fb6d989679beb685b379df60d7077cdf4f3543593af3ccfeefac826"
}
