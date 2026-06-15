# ==========================================================================
# 정적 프론트엔드 — S3(오리진) + CloudFront(CDN) + OAC
# --------------------------------------------------------------------------
# ★ 버킷은 이미 존재(siseon-frontend-client / -admin)하므로 data 소스로 참조.
#    Terraform 이 버킷을 생성/삭제하지 않음 → destroy 해도 버킷·자산 유지(팀 패턴).
#    안의 기존 테스트 파일은 CI 의 `s3 sync --delete` 첫 배포 때 정리됨.
#
# ★ 핵심 설계: admin 배포에 /api·/ws behavior 를 절대 넣지 않는다.
#    API/WS 는 api.siseon.live → GA 로만 흐른다(공존 구조).
# ==========================================================================

# AWS 관리형 캐시 정책 (정적 자산 최적화)
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# --------------------------------------------------------------------------
# 기존 S3 버킷 참조 (생성 X)
# --------------------------------------------------------------------------
data "aws_s3_bucket" "client" {
  provider = aws.frontend
  bucket   = var.client_bucket_name
}

data "aws_s3_bucket" "admin" {
  provider = aws.frontend
  bucket   = var.admin_bucket_name
}

# 퍼블릭 접근 전면 차단 (OAC 전용으로 고정) — 기존 버킷에 적용
resource "aws_s3_bucket_public_access_block" "client" {
  provider                = aws.frontend
  bucket                  = data.aws_s3_bucket.client.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "admin" {
  provider                = aws.frontend
  bucket                  = data.aws_s3_bucket.admin.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --------------------------------------------------------------------------
# Origin Access Control (OAC) — CloudFront만 S3 접근 허용
# --------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "siseon-frontend-oac"
  description                       = "OAC for siseon static frontends"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# --------------------------------------------------------------------------
# CloudFront — client (siseon.live)
# --------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "client" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.domain]
  price_class         = "PriceClass_200" # 아시아 + 미국 + 유럽 (한국/미국 커버, 비용 절감)
  comment             = "siseon client-web static"
  web_acl_id          = aws_wafv2_web_acl.cloudfront.arn

  origin {
    domain_name              = data.aws_s3_bucket.client.bucket_regional_domain_name
    origin_id                = "s3-client"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-client"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true
  }

  # SPA fallback (라우터 새로고침 시 403/404 → index.html)
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }
  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cloudfront.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = { Name = "siseon-client-cf" }
}

# --------------------------------------------------------------------------
# CloudFront — admin (app.siseon.live)  ※ 순수 정적, API behavior 없음
# --------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "admin" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = ["app.${var.domain}"]
  price_class         = "PriceClass_200"
  comment             = "siseon admin-web static"
  web_acl_id          = aws_wafv2_web_acl.cloudfront.arn

  origin {
    domain_name              = data.aws_s3_bucket.admin.bucket_regional_domain_name
    origin_id                = "s3-admin"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-admin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }
  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cloudfront.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = { Name = "siseon-admin-cf" }
}

# --------------------------------------------------------------------------
# S3 버킷 정책 — 해당 CloudFront 배포(OAC)만 GetObject 허용
# --------------------------------------------------------------------------
data "aws_iam_policy_document" "client_oac" {
  statement {
    sid       = "AllowCloudFrontOAC"
    actions   = ["s3:GetObject"]
    resources = ["${data.aws_s3_bucket.client.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.client.arn]
    }
  }
}

data "aws_iam_policy_document" "admin_oac" {
  statement {
    sid       = "AllowCloudFrontOAC"
    actions   = ["s3:GetObject"]
    resources = ["${data.aws_s3_bucket.admin.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.admin.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "client" {
  provider = aws.frontend
  bucket   = data.aws_s3_bucket.client.id
  policy   = data.aws_iam_policy_document.client_oac.json
}

resource "aws_s3_bucket_policy" "admin" {
  provider = aws.frontend
  bucket   = data.aws_s3_bucket.admin.id
  policy   = data.aws_iam_policy_document.admin_oac.json
}
