# ==========================================================================
# DR 백업 파이프라인
# ==========================================================================

# --------------------------------------------------------------------------
# 로컬 변수
# --------------------------------------------------------------------------
locals {
  backup_bucket_name = "stockops-rds-backup-${data.aws_caller_identity.current.account_id}"
}

# --------------------------------------------------------------------------
# 1. Lambda SG (rds-to-s3, s3-to-azure 공용)
#    - rds-to-s3  : DB SG inbound 허용 필요 → seoul_db_sg에 별도 ingress 추가
#    - s3-to-azure: 아웃바운드(443) → NAT GW → Azure
# --------------------------------------------------------------------------
resource "aws_security_group" "dr_backup_sg" {
  name        = "seoul-dr-backup-sg"
  description = "SG for DR backup ECS task"
  vpc_id      = module.seoul_vpc.vpc_id

  egress {
    description = "HTTPS outbound (S3 Gateway EP / NAT to Azure)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "PostgreSQL to RDS"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = { Name = "seoul-dr-backup-sg" }
}

# DB SG에 Lambda → RDS 인바운드 허용
resource "aws_security_group_rule" "db_ingress_from_dr_backup" {
  type                     = "ingress"
  description              = "Allow DR backup task to connect to RDS"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dr_backup_sg.id
  security_group_id        = aws_security_group.seoul_db_sg.id
}

# --------------------------------------------------------------------------
# 2. 백업 S3 버킷
# --------------------------------------------------------------------------
data "aws_s3_bucket" "rds_backup" {
  bucket = local.backup_bucket_name
}

# --------------------------------------------------------------------------
# 3. IAM 롤 — DR 백업 태스크 (RDS 덤프 → 백업 저장소 쓰기)
#    (Basic + VPCAccess + S3 PutObject/AbortMultipartUpload)
# --------------------------------------------------------------------------
resource "aws_iam_role" "dr_backup_task" {
  name = "seoul-dr-backup-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dr_backup_task_basic" {
  role       = aws_iam_role.dr_backup_task.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "dr_backup_task_vpc" {
  role       = aws_iam_role.dr_backup_task.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "dr_backup_task_s3_write" {
  name = "dr-backup-task-s3-write"
  role = aws_iam_role.dr_backup_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "BackupBucketWrite"
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:AbortMultipartUpload"
      ]
      Resource = [
        data.aws_s3_bucket.rds_backup.arn,
        "${data.aws_s3_bucket.rds_backup.arn}/*"
      ]
    }]
  })
}

# --------------------------------------------------------------------------
# 4. IAM 롤 — DR 리더 (백업 저장소 읽기 전용)
#    (Basic + VPCAccess + S3 ReadOnly)
# --------------------------------------------------------------------------
resource "aws_iam_role" "dr_reader" {
  name = "seoul-dr-reader-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dr_reader_basic" {
  role       = aws_iam_role.dr_reader.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "dr_reader_vpc" {
  role       = aws_iam_role.dr_reader.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "dr_reader_s3_read" {
  role       = aws_iam_role.dr_reader.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# --------------------------------------------------------------------------
# 5. ECR — dr 컨테이너 이미지용
# --------------------------------------------------------------------------
data "aws_ecr_repository" "dr_ecr" {
  name = "stockops-dr-ecr"
}

# --------------------------------------------------------------------------
# 6. EventBridge — 매주 일요일 02:00 KST (일 17:00 UTC) rds-to-s3 Lambda 실행
# --------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "weekly_rds_backup" {
  name                = "seoul-weekly-rds-backup"
  description         = "주 1회 RDS → S3 백업 트리거"
  schedule_expression = "cron(0 17 ? * SUN *)"
}

# resource "aws_cloudwatch_event_target" "rds_backup_target" {
#   rule      = aws_cloudwatch_event_rule.weekly_rds_backup.name
#   target_id = "rds-to-s3-lambda"
#   arn       = aws_lambda_function.rds_to_s3.arn
# }
#
# resource "aws_lambda_permission" "eventbridge_invoke_rds_to_s3" {
#   statement_id  = "AllowEventBridgeInvoke"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.rds_to_s3.function_name
#   principal     = "events.amazonaws.com"
#   source_arn    = aws_cloudwatch_event_rule.weekly_rds_backup.arn
# }

