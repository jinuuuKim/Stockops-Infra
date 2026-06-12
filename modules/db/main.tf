# ==========================================================================
# DB 모듈 — RDS PostgreSQL (서브넷 그룹 + 인스턴스)
# ==========================================================================

resource "aws_db_subnet_group" "this" {
  name        = "${var.region_name}-db-subnet-group"
  description = "Database subnet group for Multi-AZ RDS"
  subnet_ids  = var.priv_db_subnet_ids

  tags = {
    Name = "${var.region_name}-db-subnet-group"
  }
}

resource "aws_db_parameter_group" "stockops_pg18" {
  name   = "stockops-postgres18"
  family = "postgres18"

  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"   # static → 리부트 필요
  }
  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements,pg_tle,pg_cron"
    apply_method = "pending-reboot"   # static → 리부트 필요
  }
  parameter {
    name         = "cron.database_name"
    value        = "stockops"
    apply_method = "pending-reboot"
  }
}

resource "aws_db_instance" "this" {
  identifier     = "${var.region_name}-rds-postgres"
  engine         = "postgres"
  engine_version       = "18.4"
  instance_class = "db.t4g.micro"

  parameter_group_name = aws_db_parameter_group.stockops_pg18.name

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"

  db_name  = "stockops"
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_sg_id]
  publicly_accessible    = false

  backup_retention_period = 7
  skip_final_snapshot     = true

  # Multi-AZ는 비용 문제로 실제 배포 전에만 켜기
  # multi_az = true

  tags = {
    Name = "${var.region_name}-rds-postgres"
  }
}
