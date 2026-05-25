# ==========================================================================
# ECS 모듈 - 메인 컨테이너 인프라 및 권한, 로그 체계 정의
# ==========================================================================

# 1. 컨테이너 서비스들이 상주할 ECS 논리 클러스터 생성
resource "aws_ecs_cluster" "this" {
  name = "${var.region_name}-cluster"

  tags = {
    Name = "${var.region_name}-cluster"
  }
}

# 2. 로그 담당자 팀원을 위한 CloudWatch 로그 수집소 개설 (Spring & FastAPI 독립 수집)
resource "aws_cloudwatch_log_group" "spring" {
  name              = "/ecs/${var.region_name}-spring-app"
  retention_in_days = 7 # 개발 프로젝트용 로그 보존 기간 7일 설정 (비용 절감)
}

resource "aws_cloudwatch_log_group" "fastapi" {
  name              = "/ecs/${var.region_name}-fastapi-app"
  retention_in_days = 7
}

# 3. ECS Fargate 가 컨테이너를 실행할 때 사용할 기본 IAM execution role (보안 권한)
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.region_name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
      }
    ]
  })
}

# AWS 가 표준으로 제공하는 ECR 이미지 다운로드 및 CloudWatch 로그 기록 권한 정책 본딩
resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ==========================================================================
# 4. 애플리케이션별 태스크 정의 (Task Definitions - 컨테이너 도면)
# ==========================================================================

# --- 메인 백엔드: Spring API 태스크 도면 ---
resource "aws_ecs_task_definition" "spring" {
  family                   = "${var.region_name}-spring-task"
  network_mode             = "awsvpc" # Fargate 표준 네트워크 모드
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256" # 최소 사양 0.25 vCPU
  memory                   = "512" # 최소 사양 512 MB
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "spring-container"
      image     = "amazon/amazon-ecs-sample" # 초기 인프라 검증용 샘플 이미지 (향후 App팀이 교체)
      essential = true
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.spring.name
          "awslogs-region"        = "ap-northeast-2"
          "awslogs-stream-prefix" = "spring"
        }
      }
    }
  ])
}

# --- AI 분석 백엔드: FastAPI 태스크 도면 ---
resource "aws_ecs_task_definition" "fastapi" {
  family                   = "${var.region_name}-fastapi-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "fastapi-container"
      image     = "amazon/amazon-ecs-sample"
      essential = true
      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.fastapi.name
          "awslogs-region"        = "ap-northeast-2"
          "awslogs-stream-prefix" = "fastapi"
        }
      }
    }
  ])
}

# ==========================================================================
# 5. 애플리케이션별 ECS 서비스 정의 (Services - 컨테이너 실체 가동 및 ALB 결합)
# ==========================================================================

# --- Spring API 서비스 상시 구동 ---
resource "aws_ecs_service" "spring" {
  name            = "${var.region_name}-spring-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.spring.arn
  launch_type     = "FARGATE"
  desired_count   = 1 # 1단계 가동용 상시 컨테이너 개수 1개 설정 (도쿄 리전은 향후 0으로 세팅 예정)

  network_configuration {
    subnets          = var.priv_app_subnet_ids
    security_groups  = [var.app_sg_id]
    assign_public_ip = false # 외부 인터넷 노출 원천 차단 (보안 강화)
  }

  load_balancer {
    target_group_arn = var.spring_tg_arn
    container_name   = "spring-container"
    container_port   = 8080
  }
}

# --- FastAPI AI 서비스 상시 구동 ---
resource "aws_ecs_service" "fastapi" {
  name            = "${var.region_name}-fastapi-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.fastapi.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = var.priv_app_subnet_ids
    security_groups  = [var.app_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.fastapi_tg_arn
    container_name   = "fastapi-container"
    container_port   = 8000
  }
}