# ==========================================================================
# ALB 모듈 — 로드 밸런서, 타겟 그룹, 경로 기반 라우팅 규칙
# ==========================================================================

# ALB 보안 그룹 (인터넷 HTTP/HTTPS 허용)
resource "aws_security_group" "alb_sg" {
  name        = "${var.region_name}-alb-sg"
  description = "Allow HTTP and HTTPS traffic from internet"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.region_name}-alb-sg"
  }
}

# Application Load Balancer
resource "aws_lb" "alb" {
  name               = "${var.region_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnet_ids

  tags = {
    Name = "${var.region_name}-alb"
  }
}

# 타겟 그룹 — api-server (Port 8080)
resource "aws_lb_target_group" "spring_tg" {
  name        = "${var.region_name}-spring-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/actuator/health"
    port                = "8080"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.region_name}-spring-tg"
  }
}

# 타겟 그룹 — ai-module (Port 8000)
resource "aws_lb_target_group" "fastapi_tg" {
  name        = "${var.region_name}-fastapi-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "8000"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.region_name}-fastapi-tg"
  }
}

# HTTP 리스너 → HTTPS 리다이렉트
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS 리스너 (기본 → client-web)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

# api-server — 경로 기반 (HTTPS 리스너로 이동)
resource "aws_lb_listener_rule" "api_rule" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.spring_tg.arn
  }

  condition {
    path_pattern {
      values = ["/api", "/api/*"]
    }
  }
}

# ai-module — 경로 기반 (HTTPS 리스너로 이동)
resource "aws_lb_listener_rule" "ai_rule" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.fastapi_tg.arn
  }

  condition {
    path_pattern {
      values = ["/ai", "/ai/*"]
    }
  }
}

# WebSocket — api-server
resource "aws_lb_listener_rule" "ws_rule" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 5

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.spring_tg.arn
  }

  condition {
    path_pattern {
      values = ["/ws", "/ws/*"]
    }
  }
}
