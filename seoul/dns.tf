# ==========================================================================
# Route53 호스팅 존 + ACM — 서울
# ==========================================================================

resource "aws_route53_zone" "main" {
  name              = var.domain
  delegation_set_id = var.delegation_set_id
  tags = { Name = "${var.domain}-zone" }
}

resource "aws_acm_certificate" "seoul" {
  domain_name               = var.domain
  subject_alternative_names = ["*.${var.domain}"]
  validation_method         = "DNS"
  lifecycle { create_before_destroy = true }
  tags = { Name = "${var.domain}-cert-seoul" }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.seoul.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }
  zone_id         = aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "seoul" {
  certificate_arn         = aws_acm_certificate.seoul.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

output "acm_certificate_arn_seoul" {
  value = aws_acm_certificate_validation.seoul.certificate_arn
}

output "route53_zone_id" {
  value = aws_route53_zone.main.zone_id
}

output "route53_name_servers" {
  value = aws_route53_zone.main.name_servers
}