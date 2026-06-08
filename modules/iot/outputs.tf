# ==========================================================================
# IoT Core 모듈 — 출력 변수
# apply 후 인증서 3개와 엔드포인트를 온프레미스에 전달
# 추출: terraform output -raw certificate_pem > mosquitto-bridge.cert.pem
# ==========================================================================

output "certificate_pem" {
  description = "Mosquitto bridge_certfile용 인증서 PEM"
  value       = aws_iot_certificate.bridge.certificate_pem
  sensitive   = true
}

output "private_key" {
  description = "Mosquitto bridge_keyfile용 프라이빗 키"
  value       = aws_iot_certificate.bridge.private_key
  sensitive   = true
}

output "public_key" {
  description = "IoT 퍼블릭 키 (참고용)"
  value       = aws_iot_certificate.bridge.public_key
  sensitive   = true
}

output "iot_endpoint" {
  description = "IoT Core 엔드포인트 추출 명령어"
  value       = "aws iot describe-endpoint --endpoint-type iot:Data-ATS --profile siseon --query endpointAddress --output text"
}

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
