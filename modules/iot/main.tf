# ==========================================================================
# IoT Core 모듈 — 센서 데이터 파이프라인
# 흐름: 온프레미스 센서 → Mosquitto 브리지 → IoT Core → Rule → SQS(실시간) + Firehose→S3(이력)
# ==========================================================================

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ==========================================================================
# IoT Thing + 인증서 + 정책
# ==========================================================================

resource "aws_iot_thing" "bridge" {
  name = var.thing_name
}

resource "aws_iot_policy" "bridge" {
  name = "${var.thing_name}-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "iot:Connect"
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:client/${var.client_id}"
      },
      {
        Effect   = "Allow"
        Action   = "iot:Publish"
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/${var.topic_prefix}/*"
      },
    ]
  })
}

# Thing ↔ 인증서 ↔ 정책 연결
resource "aws_iot_thing_principal_attachment" "bridge" {
  thing     = aws_iot_thing.bridge.name
  principal = var.iot_certificate_arn
}

resource "aws_iot_policy_attachment" "bridge" {
  policy = aws_iot_policy.bridge.name
  target = var.iot_certificate_arn
}

# ==========================================================================
# SQS — 실시간 처리
# ==========================================================================

resource "aws_sqs_queue" "sensor_dlq" {
  name                      = var.sqs_dlq_name
  message_retention_seconds = 1209600 # 14일

  tags = {
    Name      = var.sqs_dlq_name
    ManagedBy = "terraform"
  }
}

resource "aws_sqs_queue" "sensor_data" {
  name                       = var.sqs_queue_name
  message_retention_seconds  = 86400 # 1일
  visibility_timeout_seconds = 30

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.sensor_dlq.arn
    maxReceiveCount     = var.dlq_max_receive_count
  })

  tags = {
    Name      = var.sqs_queue_name
    ManagedBy = "terraform"
  }
}

# IoT Rule → SQS 쓰기 허용
resource "aws_sqs_queue_policy" "sensor_data" {
  queue_url = aws_sqs_queue.sensor_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "iot.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.sensor_data.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/*"
          }
        }
      },
    ]
  })
}

# ==========================================================================
# Firehose → S3 (이력 저장)
# ==========================================================================

# 기존 S3 버킷 참조 (콘솔에서 생성)
data "aws_s3_bucket" "sensor_history" {
  bucket = "stockops-sensor-data"
}

resource "aws_iam_role" "firehose" {
  name = "stockops-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "firehose.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "firehose_s3" {
  name = "firehose-s3-write"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:GetBucketLocation",
        "s3:ListBucket",
      ]
      Resource = [
        data.aws_s3_bucket.sensor_history.arn,
        "${data.aws_s3_bucket.sensor_history.arn}/*",
      ]
    }]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "sensor_history" {
  name        = "stockops-sensor-history"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn           = aws_iam_role.firehose.arn
    bucket_arn         = data.aws_s3_bucket.sensor_history.arn
    buffering_size     = 5
    buffering_interval = 900
    compression_format = "GZIP"

    prefix              = "sensors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"
  }

  tags = {
    Name      = "stockops-sensor-history"
    ManagedBy = "terraform"
  }
}

# ==========================================================================
# IoT Rule IAM Role — SQS + Firehose 권한
# ==========================================================================

data "aws_iam_policy_document" "iot_rule_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["iot.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "iot_rule" {
  name               = "iot-sensor-rule-role"
  assume_role_policy = data.aws_iam_policy_document.iot_rule_trust.json

  tags = {
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy" "iot_rule_sqs" {
  name = "iot-rule-sqs-send"
  role = aws_iam_role.iot_rule.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.sensor_data.arn
    }]
  })
}

resource "aws_iam_role_policy" "iot_rule_firehose" {
  name = "iot-rule-firehose-put"
  role = aws_iam_role.iot_rule.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "firehose:PutRecord"
      Resource = aws_kinesis_firehose_delivery_stream.sensor_history.arn
    }]
  })
}

# ==========================================================================
# IoT Topic Rule — SQS(실시간) + Firehose(이력) 팬아웃
# ==========================================================================

resource "aws_iot_topic_rule" "sensor_fanout" {
  name        = "stockops_sensor_fanout"
  description = "센서 데이터 팬아웃 — SQS(실시간) + Firehose→S3(이력)"
  enabled     = true
  sql         = "SELECT *, topic() as mqtt_topic FROM '${var.topic_prefix}/+/sensors/+'"
  sql_version = "2016-03-23"

  sqs {
    queue_url  = aws_sqs_queue.sensor_data.url
    role_arn   = aws_iam_role.iot_rule.arn
    use_base64 = false
  }

  firehose {
    delivery_stream_name = aws_kinesis_firehose_delivery_stream.sensor_history.name
    role_arn             = aws_iam_role.iot_rule.arn
    separator            = "\n"
  }

  error_action {
    sqs {
      queue_url  = aws_sqs_queue.sensor_dlq.url
      role_arn   = aws_iam_role.iot_rule.arn
      use_base64 = false
    }
  }
}
