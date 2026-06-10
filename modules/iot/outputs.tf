# ==========================================================================
# IoT Core 모듈 — 출력 변수
# apply 후 인증서 3개와 엔드포인트를 온프레미스에 전달
# 추출: terraform output -raw certificate_pem > mosquitto-bridge.cert.pem
# ==========================================================================

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
