# ==========================================================================
# ALB 모듈 - 로드 밸런서 및 라우팅 규칙 정의
# ==========================================================================

# 1. ALB 전용 가상 방화벽 (외부의 모든 웹 트래픽 유입 허용)
resource "aws_security_group" "alb_sg" {
  name        = "${var.region_name}-alb-sg"
  description = "Allow HTTP and HTTPS traffic from internet"
  vpc_id      = var.vpc_id

  # 외부 전체(0.0.0.0/0)로부터 HTTP(80) 유입 허용
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 외부 전체(0.0.0.0/0)로부터 HTTPS(443) 유입 허용
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 아웃바운드: 내부 서브넷의 앱 서버로 트래픽을 토스하기 위해 전면 허용
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

# 2. 퍼블릭 서브넷들에 걸쳐 작동하는 애플리케이션 로드 밸런서(ALB) 생성
resource "aws_lb" "alb" {
  name               = "${var.region_name}-alb"
  internal           = false # 외부 인터넷 개방형
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnet_ids

  tags = {
    Name = "${var.region_name}-alb"
  }
}

# 1. 관리자 웹 전용 대상 그룹 정의 (Nginx 기본 포트 80 수용)
resource "aws_lb_target_group" "admin_tg" {
  name        = "${var.region_name}-admin-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # EKS Pod IP 다이렉트 타격 모드

  health_check {
    enabled             = true
    path                = "/" # Nginx 루트 경로 헬스체크
    port                = "80"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "frontend_tg" {
  name        = "${var.region_name}-frontend-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/"
    port                = "80"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

# 3. 메인 백엔드(Spring API) 타겟 그룹 정의 (Fargate 연동을 위해 target_type=ip)
resource "aws_lb_target_group" "spring_tg" {
  name        = "${var.region_name}-spring-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/actuator/health" # 상태 체크 경로
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

# 4. AI 분석 백엔드(FastAPI) 타겟 그룹 정의
resource "aws_lb_target_group" "fastapi_tg" {
  name        = "${var.region_name}-fastapi-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health" # FastAPI 기본 Swagger 문서 경로 활용
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

# 5. ALB 메인 리스너 수정 (기본 규칙을 프론트엔드로 변경)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  # [변경] 아무 조건이 없을 때 기본적으로 프론트엔드 화면(포트 80)을 보여줍니다.
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend_tg.arn
  }
}

resource "aws_lb_listener_rule" "admin_rule" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 85 # /api(90) 및 /ai(100)와 겹치지 않는 우선순위 부여

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.admin_tg.arn
  }

  condition {
    path_pattern {
      # 🌟 /admin 및 /admin/* 경로 유입 트래픽을 전담 마크합니다.
      values = ["/admin", "/admin/*"]
    }
  }
}

# 6. 기존 경로 분기 규칙 아래에 백엔드용 /api/* 라우팅 룰을 추가합니다.
resource "aws_lb_listener_rule" "api_rule" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 90 # FastAPI보다 조금 더 앞선 우선순위 설정

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

# 6. 경로 기반 라우팅 규칙 분기: /ai/* 주소 패턴은 FastAPI 서버로 포워딩
resource "aws_lb_listener_rule" "ai_rule" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100 # 라우팅 매칭 우선순위

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