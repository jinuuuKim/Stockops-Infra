# ==========================================================================
# IoT Core 모듈
# 흐름: Sensimul → Mosquitto → [브리지] → AWS IoT Core → Rule → SQS → 백엔드
# ==========================================================================

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ── 1. IoT Thing ──────────────────────────────
resource "aws_iot_thing" "bridge" {
  name = var.thing_name
}

# ── 2. 인증서 (Terraform이 생성, 파일로 출력) ──
resource "aws_iot_certificate" "bridge" {
  active = true
}

# ── 3. IoT 정책 ───────────────────────────────
# mosquitto-bridge client_id로 Connect + sensimul/sites/* Publish 허용
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
      }
    ]
  })
}

# ── 4. Thing ↔ 인증서 ↔ 정책 연결 ────────────
resource "aws_iot_thing_principal_attachment" "bridge" {
  thing     = aws_iot_thing.bridge.name
  principal = aws_iot_certificate.bridge.arn
}

resource "aws_iot_policy_attachment" "bridge" {
  policy = aws_iot_policy.bridge.name
  target = aws_iot_certificate.bridge.arn
}

# ── 5. SQS DLQ ────────────────────────────────
resource "aws_sqs_queue" "sensor_dlq" {
  name                      = var.sqs_dlq_name
  message_retention_seconds = 1209600 # 14일

  tags = {
    Name      = var.sqs_dlq_name
    ManagedBy = "terraform"
  }
}

# ── 6. SQS 메인 큐 ────────────────────────────
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

# IoT Rule이 SQS에 쓸 수 있도록 큐 정책 허용
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
      }
    ]
  })
}

# ── 7. IoT Rule용 IAM Role ────────────────────
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
      }
    ]
  })
}

# ── 8. IoT Rule ───────────────────────────────
# sensimul/sites/+/sensors/+ 토픽의 모든 메시지를 SQS로 전달
resource "aws_iot_topic_rule" "sensor_to_sqs" {
  name        = "stockops_sensor_to_sqs"
  description = "센시뮬 센서 데이터를 SQS로 라우팅"
  enabled     = true
  sql         = "SELECT *, topic() as mqtt_topic FROM '${var.topic_prefix}/+/sensors/+'"
  sql_version = "2016-03-23"

  sqs {
    queue_url  = aws_sqs_queue.sensor_data.url
    role_arn   = aws_iam_role.iot_rule.arn
    use_base64 = false
  }

  # Rule 실패 시 DLQ로
  error_action {
    sqs {
      queue_url  = aws_sqs_queue.sensor_dlq.url
      role_arn   = aws_iam_role.iot_rule.arn
      use_base64 = false
    }
  }
}
