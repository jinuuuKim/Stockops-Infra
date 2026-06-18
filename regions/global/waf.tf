# ==========================================================================
# 글로벌 리소스 — WAF 설정
# ==========================================================================

# CLOUDFRONT scope WebACL은 반드시 us-east-1에 생성.
# provider 별칭은 기존 global에 정의된 virginia를 사용한다고 가정.
resource "aws_wafv2_web_acl" "cloudfront" {
  provider = aws.virginia

  name        = "stockops-cloudfront-waf"
  description = "CLOUDFRONT WebACL for client/admin distributions"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "cf-CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "cf-IpReputation"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "stockops-cloudfront-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_cloudwatch_log_group" "waf_cloudfront" {
  provider          = aws.virginia
  name              = "aws-waf-logs-stockops-cloudfront"
  retention_in_days = 7
}
 
resource "aws_wafv2_web_acl_logging_configuration" "cloudfront" {
  provider                = aws.virginia
  resource_arn            = aws_wafv2_web_acl.cloudfront.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf_cloudfront.arn]
}