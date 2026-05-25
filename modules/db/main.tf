# ==========================================================================
# DB 모듈 - 메인 RDS 인프라 자원 정의 (Subnet Group, DB Instance)
# ==========================================================================

# 1. 다중 가용영역 서브넷들을 하나로 묶는 데이터베이스 서브넷 그룹 생성
resource "aws_db_subnet_group" "this" {
  name        = "${var.region_name}-db-subnet-group"
  description = "Database subnet group for Multi-AZ RDS"
  subnet_ids  = var.priv_db_subnet_ids

  tags = {
    Name = "${var.region_name}-db-subnet-group"
  }
}

# 2. 완전 관리형 RDS PostgreSQL 데이터베이스 인스턴스 생성
resource "aws_db_instance" "this" {
  identifier             = "${var.region_name}-rds-postgres"
  engine                 = "postgres"
  engine_version         = "16"             # PostgreSQL 최신 안정 버전 적용
  instance_class         = "db.t4g.micro"     # 비용 효율적인 AWS Graviton3 기반 인스턴스 사양
  
  # --- 스토리지 설정 ---
  allocated_storage     = 20                  # 기본 할당 크기 20GB (최소 스펙)
  max_allocated_storage = 100                 # 스토리지 자동 확장 임계치 (최대 100GB까지 자동 스케일 업)
  storage_type          = "gp3"               # 가성비가 가장 좋은 최신 범용 SSD 스토리지 타입

  # --- 데이터베이스 및 계정 설정 ---
  db_name                = "stockops"         # 최초 자동 생성될 초기 데이터베이스 이름
  username               = var.db_username
  password               = var.db_password
  
  # --- 네트워크 및 보안 연결 ---
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_sg_id]     # 애플리케이션 서버만 허용하는 보안그룹 연동
  publicly_accessible    = false              # 외부 인터넷을 통한 다이렉트 커넥션 원천 차단

  # --- 백업 및 유지보수 ---
  backup_retention_period = 7                 # 자동 백업 보존 기간 7일 설정 (2단계 크로스 백업 준비용)
  skip_final_snapshot     = true              # 프로젝트 삭제 및 테스트 시 빠른 자원 해제를 위해 최종 스냅샷 생략

  tags = {
    Name = "${var.region_name}-rds-postgres"
  }
}