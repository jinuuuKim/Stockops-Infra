# ==========================================================================
# CloudFront용 ACM 인증서 (us-east-1 / Virginia)
# --------------------------------------------------------------------------
# CloudFront viewer_certificate 는 반드시 us-east-1 인증서만 허용.
# siseon.live(클라이언트) + *.siseon.live(app.siseon.live 어드민) 커버.
# 검증 레코드는 seoul state가 소유한 Route53 존에 생성(allow_overwrite로 공존).
# ==========================================================================

resource "aws_acm_certificate" "cloudfront" {
  provider                  = aws.virginia
  domain_name               = var.domain
  subject_alternative_names = ["*.${var.domain}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.domain}-cert-cloudfront" }
}

resource "aws_route53_record" "cloudfront_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cloudfront.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  # seoul state가 hosted zone 소유 → remote_state 로 zone_id 참조
  zone_id         = data.terraform_remote_state.seoul.outputs.route53_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cloudfront" {
  provider                = aws.virginia
  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [for r in aws_route53_record.cloudfront_cert_validation : r.fqdn]
}
