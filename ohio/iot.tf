# ==========================================================================
# 오하이오 IoT — 페일오버용 SQS 파이프라인
# 평상시: Rule enabled=false (IoT Core 수신은 하되 SQS로 흘리지 않음)
# 페일오버 시: enabled=true로 변경 후 apply
# ==========================================================================

# --------------------------------------------------------------------------
# SQS — 실시간 처리
# --------------------------------------------------------------------------
resource "aws_sqs_queue" "sensor_dlq" {
  provider                  = aws.ohio
  name                      = "stockops-sensor-data-dlq"
  message_retention_seconds = 1209600

  tags = {
    Name      = "stockops-sensor-data-dlq"
    ManagedBy = "terraform"
  }
}

resource "aws_sqs_queue" "sensor_data" {
  provider                   = aws.ohio
  name                       = "stockops-sensor-data"
  message_retention_seconds  = 86400
  visibility_timeout_seconds = 30

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.sensor_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name      = "stockops-sensor-data"
    ManagedBy = "terraform"
  }
}

resource "aws_sqs_queue_policy" "sensor_data" {
  provider  = aws.ohio
  queue_url = aws_sqs_queue.sensor_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "iot.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.sensor_data.arn
      Condition = {
        ArnLike = {
          "aws:SourceArn" = "arn:aws:iot:us-east-2:${data.aws_caller_identity.current.account_id}:rule/*"
        }
      }
    }]
  })
}

# --------------------------------------------------------------------------
# IoT Rule IAM Role
# --------------------------------------------------------------------------
resource "aws_iam_role" "ohio_iot_rule" {
  provider = aws.ohio
  name     = "ohio-iot-sensor-rule-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "iot.amazonaws.com" }
    }]
  })

  tags = { ManagedBy = "terraform" }
}

resource "aws_iam_role_policy" "ohio_iot_rule_sqs" {
  provider = aws.ohio
  name     = "ohio-iot-rule-sqs-send"
  role     = aws_iam_role.ohio_iot_rule.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.sensor_data.arn
    }]
  })
}

# --------------------------------------------------------------------------
# IoT Topic Rule — SQS만 (Firehose 없음)
# enabled = false → 평상시 비활성, 페일오버 시 true로 변경
# --------------------------------------------------------------------------
resource "aws_iot_topic_rule" "sensor_fanout" {
  provider    = aws.ohio
  name        = "stockops_sensor_fanout"
  description = "센서 데이터 SQS 팬아웃 (페일오버 전용)"
  enabled     = false   # 페일오버 시 true로 변경
  sql         = "SELECT *, topic() as mqtt_topic FROM 'sensimul/sites/+/sensors/+'"
  sql_version = "2016-03-23"

  sqs {
    queue_url  = aws_sqs_queue.sensor_data.url
    role_arn   = aws_iam_role.ohio_iot_rule.arn
    use_base64 = false
  }

  error_action {
    sqs {
      queue_url  = aws_sqs_queue.sensor_dlq.url
      role_arn   = aws_iam_role.ohio_iot_rule.arn
      use_base64 = false
    }
  }
}