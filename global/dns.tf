# ==========================================================================
# Route53 A 레코드 — GA 연결
# ==========================================================================

resource "aws_route53_record" "root" {
  zone_id = data.terraform_remote_state.seoul.outputs.route53_zone_id
  name    = "mellohn.cloud"
  type    = "A"
  alias {
    name                   = aws_globalaccelerator_accelerator.stockops.dns_name
    zone_id                = "Z2BJ6XQ5FK7U4H"
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "admin" {
  zone_id = data.terraform_remote_state.seoul.outputs.route53_zone_id
  name    = "admin.mellohn.cloud"
  type    = "A"
  alias {
    name                   = aws_globalaccelerator_accelerator.stockops.dns_name
    zone_id                = "Z2BJ6XQ5FK7U4H"
    evaluate_target_health = false
  }
}