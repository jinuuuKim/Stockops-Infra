# ==========================================================================
# 글로벌 리소스 — Global Accelerator
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

# data "terraform_remote_state" "ohio" {
#   backend = "s3"
#   config = {
#     bucket  = "siseon-terraform-state"
#     key     = "infra/ohio/terraform.tfstate"
#     region  = "ap-northeast-2"
#     profile = "siseon"
#   }
# }

resource "aws_globalaccelerator_accelerator" "stockops" {
  name            = "stockops-global-accelerator"
  ip_address_type = "IPV4"
  enabled         = true
  tags = {
    Name      = "stockops-global-accelerator"
    ManagedBy = "terraform"
  }
}

resource "aws_globalaccelerator_listener" "http" {
  accelerator_arn = aws_globalaccelerator_accelerator.stockops.id
  protocol        = "TCP"
  port_range {
    from_port = 80
    to_port   = 80
  }
}

resource "aws_globalaccelerator_listener" "https" {
  accelerator_arn = aws_globalaccelerator_accelerator.stockops.id
  protocol        = "TCP"
  port_range {
    from_port = 443
    to_port   = 443
  }
}

resource "aws_globalaccelerator_endpoint_group" "seoul_http" {
  listener_arn                  = aws_globalaccelerator_listener.http.id
  endpoint_group_region         = "ap-northeast-2"
  traffic_dial_percentage       = 100
  health_check_path             = "/"
  health_check_protocol         = "HTTP"
  health_check_interval_seconds = 30
  threshold_count               = 3
  endpoint_configuration {
    endpoint_id                    = data.terraform_remote_state.seoul.outputs.seoul_alb_arn
    weight                         = 100
    client_ip_preservation_enabled = true
  }
}

resource "aws_globalaccelerator_endpoint_group" "seoul_https" {
  listener_arn                  = aws_globalaccelerator_listener.https.id
  endpoint_group_region         = "ap-northeast-2"
  traffic_dial_percentage       = 100
  health_check_path             = "/"
  health_check_protocol         = "HTTPS"
  health_check_interval_seconds = 30
  threshold_count               = 3
  endpoint_configuration {
    endpoint_id                    = data.terraform_remote_state.seoul.outputs.seoul_alb_arn
    weight                         = 100
    client_ip_preservation_enabled = true
  }
}

# resource "aws_globalaccelerator_endpoint_group" "ohio_http" {
#   listener_arn                  = aws_globalaccelerator_listener.http.id
#   endpoint_group_region         = "us-east-2"
#   traffic_dial_percentage       = 100
#   health_check_path             = "/"
#   health_check_protocol         = "HTTP"
#   health_check_interval_seconds = 30
#   threshold_count               = 3
#   endpoint_configuration {
#     endpoint_id                    = data.terraform_remote_state.ohio.outputs.ohio_alb_arn
#     weight                         = 100
#     client_ip_preservation_enabled = true
#   }
# }

# resource "aws_globalaccelerator_endpoint_group" "ohio_https" {
#   listener_arn                  = aws_globalaccelerator_listener.https.id
#   endpoint_group_region         = "us-east-2"
#   traffic_dial_percentage       = 100
#   health_check_path             = "/"
#   health_check_protocol         = "HTTPS"
#   health_check_interval_seconds = 30
#   threshold_count               = 3
#   endpoint_configuration {
#     endpoint_id                    = data.terraform_remote_state.ohio.outputs.ohio_alb_arn
#     weight                         = 100
#     client_ip_preservation_enabled = true
#   }
# }