# ==========================================================================
# seoul/iot.tf
# ==========================================================================

module "seoul_iot" {
  source = "../modules/iot"

  thing_name     = "mosquitto-bridge"
  topic_prefix   = "sensimul/sites"
  sqs_queue_name = "stockops-sensor-data"
  sqs_dlq_name   = "stockops-sensor-data-dlq"
}

output "sensor_sqs_queue_url" {
  value = module.seoul_iot.sqs_queue_url
}
