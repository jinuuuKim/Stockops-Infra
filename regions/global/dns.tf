# ==========================================================================
# Route53 A 레코드 — 공존 구조(도메인 분리)
# --------------------------------------------------------------------------
#   siseon.live      → CloudFront(client) → S3   ... 정적 (캐시 O)
#   app.siseon.live  → CloudFront(admin)  → S3   ... 정적 (캐시 O)
#   api.siseon.live  → GA → 가까운 리전 ALB       ... 동적 (캐시 X, 멀티리전)
#
#   ※ 핵심: API 가 CloudFront 를 거치지 않으므로 GA 가 진짜 클라이언트 IP 를
#           인식 → 한국=서울 / 미국=오하이오 지연 기반 라우팅이 살아있음.
# ==========================================================================

# 정적 — client
resource "aws_route53_record" "root" {
  zone_id = data.terraform_remote_state.seoul.outputs.route53_zone_id
  name    = var.domain
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.client.domain_name
    zone_id                = aws_cloudfront_distribution.client.hosted_zone_id
    evaluate_target_health = false
  }
}

# 정적 — admin
resource "aws_route53_record" "app" {
  zone_id = data.terraform_remote_state.seoul.outputs.route53_zone_id
  name    = "app.${var.domain}"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.admin.domain_name
    zone_id                = aws_cloudfront_distribution.admin.hosted_zone_id
    evaluate_target_health = false
  }
}

# 동적 — API/WS/AI (GA 경유, 멀티리전 라우팅 유지)
resource "aws_route53_record" "api" {
  zone_id = data.terraform_remote_state.seoul.outputs.route53_zone_id
  name    = "api.${var.domain}"
  type    = "A"
  alias {
    name                   = aws_globalaccelerator_accelerator.stockops.dns_name
    zone_id                = aws_globalaccelerator_accelerator.stockops.hosted_zone_id
    evaluate_target_health = false
  }
}
