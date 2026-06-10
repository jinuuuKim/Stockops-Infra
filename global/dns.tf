# ==========================================================================
# Route53 A 레코드 — GA 연결
# ==========================================================================

resource "aws_route53_record" "root" {
  zone_id = data.terraform_remote_state.seoul.outputs.route53_zone_id
  name    = var.domain
  type    = "A"
  alias {
    name                   = aws_globalaccelerator_accelerator.stockops.dns_name
    zone_id                = aws_globalaccelerator_accelerator.stockops.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "app" {
  zone_id = data.terraform_remote_state.seoul.outputs.route53_zone_id
  name    = "app.${var.domain}"
  type    = "A"
  alias {
    name                   = aws_globalaccelerator_accelerator.stockops.dns_name
    zone_id                = aws_globalaccelerator_accelerator.stockops.hosted_zone_id
    evaluate_target_health = false
  }
}