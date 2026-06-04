# ==========================================================================
# 서울 리전 전용 서비스별 가상 방화벽 (Security Groups) - 충돌 해결 완결판
# ==========================================================================

# 1. 서울 애플리케이션용 방화벽 본체 (규칙은 하단에서 독립형 리소스로 제어합니다)
resource "aws_security_group" "seoul_app_sg" {
  name        = "seoul-app-sg"
  description = "Allow inbound traffic from Seoul ALB to EKS Worker Nodes"
  vpc_id      = module.seoul_vpc.vpc_id

  # 🌟 [중요] 내부 인라인 ingress 블록을 전부 제거하여 방화벽 규칙 충돌을 원천 차단합니다.
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

# 2. 서울 데이터베이스(RDS)용 방화벽 본체
resource "aws_security_group" "seoul_db_sg" {
  name        = "seoul-db-sg"
  description = "Allow inbound database traffic only from Seoul Apps"
  vpc_id      = module.seoul_vpc.vpc_id

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

# ==========================================================================
# 애플리케이션 방화벽(App SG) 전용 인바운드 규칙 정의 (ALB -> Pod 통로 개설)
# ==========================================================================

resource "aws_security_group_rule" "alb_to_nodes_frontend" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  # 🌟 [교정] 유령 방화벽 대신 EKS 실제 노드 방화벽 ID로 목적지를 바꿉니다!
  security_group_id        = module.seoul_eks.cluster_security_group_id
  source_security_group_id = module.seoul_alb.alb_sg_id
}

resource "aws_security_group_rule" "alb_to_nodes_backend" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  # 🌟 [교정] EKS 실제 노드 방화벽 ID로 목적지 동기화
  security_group_id        = module.seoul_eks.cluster_security_group_id
  source_security_group_id = module.seoul_alb.alb_sg_id
}

resource "aws_security_group_rule" "alb_to_nodes_fastapi" {
  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  # 🌟 [교정] EKS 실제 노드 방화벽 ID로 목적지 동기화
  security_group_id        = module.seoul_eks.cluster_security_group_id
  source_security_group_id = module.seoul_alb.alb_sg_id
}

# ==========================================================================
# 데이터베이스 방화벽(DB SG) 전용 인바운드 규칙 정의
# ==========================================================================

# 규칙 A: 오직 내부 App 방화벽을 가진 컨테이너의 접근만 허용합니다.
resource "aws_security_group_rule" "app_to_db" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.seoul_db_sg.id
  source_security_group_id = aws_security_group.seoul_app_sg.id
}

# 규칙 B: VPC 내부 전체 사설망 대역에서의 개발 테스트용 접근을 허용합니다.
resource "aws_security_group_rule" "vpc_internal_to_db" {
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  security_group_id = aws_security_group.seoul_db_sg.id
  cidr_blocks       = ["10.0.0.0/16"]
}