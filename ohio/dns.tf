# ==========================================================================
# ACM — 오하이오
# ==========================================================================

data "terraform_remote_state" "seoul" {
  backend = "s3"
  config = {
    bucket  = "siseon-terraform-state"
    key     = "infra/seoul/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "siseon"
  }
}

resource "aws_acm_certificate" "ohio" {
  domain_name               = var.domain
  subject_alternative_names = ["*.${var.domain}"]
  validation_method         = "DNS"
  lifecycle { create_before_destroy = true }
  tags = { Name = "${var.domain}-cert-ohio" }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.ohio.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }
  zone_id         = data.terraform_remote_state.seoul.outputs.route53_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "ohio" {
  certificate_arn         = aws_acm_certificate.ohio.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

output "acm_certificate_arn_ohio" {
  value = aws_acm_certificate_validation.ohio.certificate_arn
}