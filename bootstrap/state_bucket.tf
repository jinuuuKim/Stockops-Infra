# ==========================================================================
# 기존 state 버킷(siseon-terraform-state) 하드닝
# 버킷 리소스 자체는 소유하지 않고(이미 존재), 하위 설정만 적용한다.
# → import 없이 versioning/공개차단/기본암호화/정책만 건다.
# ==========================================================================

# 1) 퍼블릭 액세스 전면 차단
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = local.state_bucket
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 2) 버전닝 (실수/손상 시 이전 state 복구)
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = local.state_bucket
  versioning_configuration {
    status = "Enabled"
  }
}

# 3) 기본 SSE-KMS (이후 PutObject 는 자동 KMS 암호화)
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = local.state_bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.tfstate.arn
    }
    bucket_key_enabled = true # KMS 호출 비용 절감
  }
}

# 4) 버킷 정책 — 비-TLS 접근 거부 (안전, 락아웃 위험 없음)
resource "aws_s3_bucket_policy" "tfstate" {
  bucket = local.state_bucket
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        "arn:aws:s3:::${local.state_bucket}",
        "arn:aws:s3:::${local.state_bucket}/*"
      ]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
    # (선택·주의) 접근 주체 최소화는 락아웃 위험이 있어 마감 후 별도 검토 권장.
    #  특정 role 만 허용하려면 위 Deny 에 더해 NotPrincipal 조건을 신중히 추가.
  })
}
