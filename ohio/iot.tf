# ==========================================================================
# 오하이오 IoT — 페일오버용 SQS 파이프라인
# 평상시: Rule enabled=false (IoT Core 수신은 하되 SQS로 흘리지 않음)
# 페일오버 시: enabled=true로 변경 후 apply
# ==========================================================================

# --------------------------------------------------------------------------
# IoT Thing + 정책 + 인증서 연결 (서울과 동일 구조, us-east-2 인증서)
# 페일오버 시 디바이스가 오하이오 IoT Core에 연결하기 위해 필요
# --------------------------------------------------------------------------
resource "aws_iot_thing" "bridge" {
  provider = aws.ohio
  name     = "mosquitto-bridge"
}

resource "aws_iot_policy" "bridge" {
  provider = aws.ohio
  name     = "mosquitto-bridge-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "iot:Connect"
        Resource = "arn:aws:iot:us-east-2:${data.aws_caller_identity.current.account_id}:client/mosquitto-bridge-ohio"
      },
      {
        Effect   = "Allow"
        Action   = "iot:Publish"
        Resource = "arn:aws:iot:us-east-2:${data.aws_caller_identity.current.account_id}:topic/sensimul/sites/*"
      },
    ]
  })
}

resource "aws_iot_thing_principal_attachment" "bridge" {
  provider  = aws.ohio
  thing     = aws_iot_thing.bridge.name
  principal = "arn:aws:iot:us-east-2:448768137813:cert/d3e9b7f10ce8281a093eb2da02d09b759a31aa13d0a2ff9f27480a2f64d1e098"
}

resource "aws_iot_policy_attachment" "bridge" {
  provider = aws.ohio
  policy   = aws_iot_policy.bridge.name
  target   = "arn:aws:iot:us-east-2:448768137813:cert/d3e9b7f10ce8281a093eb2da02d09b759a31aa13d0a2ff9f27480a2f64d1e098"
}

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
  enabled     = true
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

data "aws_iam_policy_document" "api_sqs_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.ohio_eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.ohio_eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:stockops:stockops-api-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.ohio_eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "api_sqs" {
  name               = "stockops-api-sqs-role-ohio"   # 서울과 이름 충돌 방지
  assume_role_policy = data.aws_iam_policy_document.api_sqs_assume.json
}

resource "aws_iam_role_policy" "api_sqs" {
  name = "stockops-api-sqs-consume"
  role = aws_iam_role.api_sqs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:ChangeMessageVisibility",
      ]
      Resource = aws_sqs_queue.sensor_data.arn   # ← 오하이오 자기 큐
    }]
  })
}