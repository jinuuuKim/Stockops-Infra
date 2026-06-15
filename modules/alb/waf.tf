# ==========================================================================
# ALB 모듈 —  WAF 설정
# ==========================================================================


# REGIONAL scope — ALB 연결용. count로 토글
resource "aws_wafv2_web_acl" "this" {
  count = var.enable_waf ? 1 : 0

  name        = "${var.region_name}-alb-waf"
  description = "REGIONAL WebACL for ${var.region_name} ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # 1) Common Rule Set — 관찰 모드(count)로 시작
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

        # JSON API 오탐 후보 룰 — 그룹 자체가 count라 중복이지만,
        # 그룹을 block 전환할 때 이 룰들만 계속 count 유지하려고 명시해 둠
        rule_action_override {
          name = "SizeRestrictions_BODY"
          action_to_use {
            count {}
          }
        }
        rule_action_override {
          name = "CrossSiteScripting_BODY"
          action_to_use {
            count {}
          }
        }
        rule_action_override {
          name = "NoUserAgent_HEADER"
          action_to_use {
            count {}
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.region_name}-CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # 2) Known Bad Inputs — 처음부터 block (none = 그룹 기본 액션 따름)
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.region_name}-KnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  # 3) SQLi — 관찰 모드(count)로 시작
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 3

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.region_name}-SQLi"
      sampled_requests_enabled   = true
    }
  }

  # 4) 로그인 경로 전용 RateLimit — 브루트포스 방어 (100/5분)
  rule {
    name     = "LoginRateLimit"
    priority = 4

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 100
        aggregate_key_type = "IP"

        scope_down_statement {
          byte_match_statement {
            search_string         = "/api/v1/auth/login"
            positional_constraint = "STARTS_WITH"

            field_to_match {
              uri_path {}
            }

            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.region_name}-LoginRateLimit"
      sampled_requests_enabled   = true
    }
  }

  # 5) 전체 경로 RateLimit (2000/5분)
  rule {
    name     = "RateLimit"
    priority = 5

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.region_name}-RateLimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.region_name}-alb-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "this" {
  count = var.enable_waf ? 1 : 0

  resource_arn = aws_lb.alb.arn
  web_acl_arn  = aws_wafv2_web_acl.this[0].arn
}
