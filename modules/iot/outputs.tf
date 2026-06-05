# ==========================================================================
# IoT 모듈 - 출력 변수
# apply 후 팀장님께 인증서 파일 3개와 엔드포인트를 전달해야 합니다.
# ==========================================================================

# ── 인증서 파일 내용 (팀장님 전달용) ─────────
# 주의: sensitive = true 이므로 output 보려면
#       terraform output -raw <name> > <filename> 으로 추출
output "certificate_pem" {
  description = "bridge_certfile에 넣을 인증서 (mosquitto-bridge.cert.pem)"
  value       = aws_iot_certificate.bridge.certificate_pem
  sensitive   = true
}

output "private_key" {
  description = "bridge_keyfile에 넣을 프라이빗 키 (mosquitto-bridge.private.key)"
  value       = aws_iot_certificate.bridge.private_key
  sensitive   = true
}

output "public_key" {
  description = "퍼블릭 키 (참고용)"
  value       = aws_iot_certificate.bridge.public_key
  sensitive   = true
}

# ── IoT Core 엔드포인트 ────────────────────────
output "iot_endpoint" {
  description = "Mosquitto 브리지 address에 넣을 IoT Core 엔드포인트 (포트 8883)"
  value       = "추출 방법: aws iot describe-endpoint --endpoint-type iot:Data-ATS --profile siseon --query endpointAddress --output text"
}

# ── SQS ───────────────────────────────────────
output "sqs_queue_url" {
  description = "백엔드가 consume할 SQS 큐 URL"
  value       = aws_sqs_queue.sensor_data.url
}

output "sqs_queue_arn" {
  description = "SQS 큐 ARN"
  value       = aws_sqs_queue.sensor_data.arn
}

output "sqs_dlq_url" {
  description = "Dead Letter Queue URL"
  value       = aws_sqs_queue.sensor_dlq.url
}
