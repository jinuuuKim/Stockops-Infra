# ==========================================================================
# IoT Core 모듈 — 센서 데이터 파이프라인
# 흐름: 온프레미스 센서 → Mosquitto 브리지 → IoT Core → Rule → SQS → 백엔드
# ==========================================================================

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# IoT Thing
resource "aws_iot_thing" "bridge" {
  name = var.thing_name
}

# X.509 인증서 (Terraform 생성, apply 후 팀장님께 전달)
resource "aws_iot_certificate" "bridge" {
  active = true
}

# IoT 정책 (Connect + Publish 허용)
resource "aws_iot_policy" "bridge" {
  name = "${var.thing_name}-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "iot:Connect"
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:client/${var.thing_name}"
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
  principal = aws_iot_certificate.bridge.arn
}

resource "aws_iot_policy_attachment" "bridge" {
  policy = aws_iot_policy.bridge.name
  target = aws_iot_certificate.bridge.arn
}

# SQS Dead Letter Queue
resource "aws_sqs_queue" "sensor_dlq" {
  name                      = var.sqs_dlq_name
  message_retention_seconds = 1209600 # 14일

  tags = {
    Name      = var.sqs_dlq_name
    ManagedBy = "terraform"
  }
}

# SQS 메인 큐
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

# IoT Rule이 SQS에 메시지를 쓸 수 있도록 큐 정책 허용
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

# IoT Rule용 IAM Role
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
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.sensor_data.arn
      },
    ]
  })
}

# IoT Topic Rule (sensimul/sites/+/sensors/+ → SQS)
resource "aws_iot_topic_rule" "sensor_to_sqs" {
  name        = "stockops_sensor_to_sqs"
  description = "센서 데이터를 SQS로 라우팅"
  enabled     = true
  sql         = "SELECT *, topic() as mqtt_topic FROM '${var.topic_prefix}/+/sensors/+'"
  sql_version = "2016-03-23"

  sqs {
    queue_url  = aws_sqs_queue.sensor_data.url
    role_arn   = aws_iam_role.iot_rule.arn
    use_base64 = false
  }

  error_action {
    sqs {
      queue_url  = aws_sqs_queue.sensor_dlq.url
      role_arn   = aws_iam_role.iot_rule.arn
      use_base64 = false
    }
  }
}
