# ==========================================================================
# 오하이오 리전 — 보안 그룹 정의
# ==========================================================================

# 애플리케이션 보안 그룹 (ALB → EKS 노드 트래픽 허용)
resource "aws_security_group" "ohio_app_sg" {
  name        = "ohio-app-sg"
  description = "Allow inbound traffic from Ohio ALB to EKS Worker Nodes"
  vpc_id      = module.ohio_vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ohio-app-sg"
  }
}

# 데이터베이스 보안 그룹 (앱에서 RDS로의 접근만 허용)
resource "aws_security_group" "ohio_db_sg" {
  name        = "ohio-db-sg"
  description = "Allow inbound database traffic only from Ohio Apps"
  vpc_id      = module.ohio_vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ohio-db-sg"
  }
}

# ALB → EKS 노드 인바운드 규칙 (포트별 분리)
resource "aws_security_group_rule" "alb_to_nodes_frontend" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = module.ohio_eks.cluster_security_group_id
  source_security_group_id = module.ohio_alb.alb_sg_id
}

resource "aws_security_group_rule" "alb_to_nodes_backend" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = module.ohio_eks.cluster_security_group_id
  source_security_group_id = module.ohio_alb.alb_sg_id
}

resource "aws_security_group_rule" "alb_to_nodes_fastapi" {
  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  security_group_id        = module.ohio_eks.cluster_security_group_id
  source_security_group_id = module.ohio_alb.alb_sg_id
}

# DB 인바운드 규칙
resource "aws_security_group_rule" "app_to_db" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ohio_db_sg.id
  source_security_group_id = aws_security_group.ohio_app_sg.id
}

# VPC 내부 전 대역 DB 접근 (개발/테스트용)
resource "aws_security_group_rule" "vpc_internal_to_db" {
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  security_group_id = aws_security_group.ohio_db_sg.id
  cidr_blocks       = ["10.1.0.0/16"]
}