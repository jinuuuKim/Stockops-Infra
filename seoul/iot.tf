# ==========================================================================
# 서울 리전 — IoT Core 파이프라인
# 흐름: 온프레미스 센서 → Mosquitto 브리지 → IoT Core → SQS → 백엔드
# ==========================================================================

module "seoul_iot" {
  source = "../modules/iot"

  thing_name     = "mosquitto-bridge"
  client_id      = "mosquitto-bridge-seoul"
  topic_prefix   = "sensimul/sites"
  sqs_queue_name = "stockops-sensor-data"
  sqs_dlq_name   = "stockops-sensor-data-dlq"
  iot_certificate_arn = "arn:aws:iot:ap-northeast-2:448768137813:cert/c4ac7c856fb6d989679beb685b379df60d7077cdf4f3543593af3ccfeefac826"
}

# api-server 파드가 센서 SQS를 consume하기 위한 IRSA
data "aws_iam_policy_document" "api_sqs_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.seoul_eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.seoul_eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:stockops:stockops-api-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.seoul_eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "api_sqs" {
  name               = "stockops-api-sqs-role"
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
      Resource = module.seoul_iot.sqs_queue_arn   # 기존 output 그대로 사용
    }]
  })
}