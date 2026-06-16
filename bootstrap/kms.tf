# ==========================================================================
# state 암호화용 KMS 키
# 키 정책: 계정 root 풀 위임 → AdministratorAccess(SSO) 가 IAM 으로 kms 사용 가능.
#          (락아웃 방지의 핵심 — 운영자가 키 접근을 잃지 않게 root 에 위임)
# ==========================================================================
resource "aws_kms_key" "tfstate" {
  description             = "siseon terraform state encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EnableRootDelegation"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })

  tags = { Name = "siseon-tfstate", ManagedBy = "terraform-bootstrap" }
}

resource "aws_kms_alias" "tfstate" {
  name          = "alias/siseon-tfstate"
  target_key_id = aws_kms_key.tfstate.key_id
}
