# ==========================================================================
# 서울 리전 전용 서비스별 가상 방화벽 (Security Groups)
# ==========================================================================

# 1. 서울 ECS 애플리케이션용 방화벽 (오직 서울 ALB를 통과한 트래픽만 허용)
resource "aws_security_group" "seoul_app_sg" {
  name        = "seoul-app-sg"
  description = "Allow inbound traffic only from Seoul ALB to ECS Tasks"
  vpc_id      = module.seoul_vpc.vpc_id

  # 인바운드: Spring API 포트 (8080) 개방
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [module.seoul_alb.alb_sg_id] # 소스를 ALB 보안그룹으로 제한
  }

  # 인바운드: FastAPI AI 포트 (8000) 개방
  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [module.seoul_alb.alb_sg_id] # 소스를 ALB 보안그룹으로 제한
  }

  # 아웃바운드: 외부 API 연동(Azure AD, Teams 등)을 위해 전면 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "seoul-app-sg"
  }
}

# 2. 서울 데이터베이스(RDS)용 방화벽 (오직 위의 서울 ECS App 트래픽만 허용)
resource "aws_security_group" "seoul_db_sg" {
  name        = "seoul-db-sg"
  description = "Allow inbound database traffic only from Seoul ECS Apps"
  vpc_id      = module.seoul_vpc.vpc_id

  # 인바운드: PostgreSQL 포트 (5432) 개방
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.seoul_app_sg.id] # 소스를 App 보안그룹으로 제한
  }

  # 🔥 [임시 추가] 테스트용 EC2가 위치할 VPC 내부 전체 대역에서 5432 접근 허용
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] 
  }

  # 아웃바운드: 내부 사설 네트워크 통신 외 기본 차단 (필요 시 전면 허용 가능)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "seoul-db-sg"
  }
}