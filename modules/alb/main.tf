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

# 3. 메인 백엔드(Spring API) 타겟 그룹 정의 (Fargate 연동을 위해 target_type=ip)
resource "aws_lb_target_group" "spring_tg" {
  name        = "${var.region_name}-spring-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/" # 상태 체크 경로
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
    path                = "/docs" # FastAPI 기본 Swagger 문서 경로 활용
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

# 5. ALB 메인 리스너 (80포트로 진입 시 기본 액션 제어)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  # 기본 규칙: 매칭되는 특수 경로가 없으면 기본 백엔드(Spring)로 전달
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.spring_tg.arn
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
      values = ["/ai/*"]
    }
  }
}