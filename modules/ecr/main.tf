# ==========================================================================
# ECR 모듈 — 프라이빗 컨테이너 이미지 저장소
# ==========================================================================

resource "aws_ecr_repository" "app_repo" {
  name                 = var.repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }
}

# 최신 10개 이미지만 유지, 이전 이미지 자동 삭제
resource "aws_ecr_lifecycle_policy" "app_repo_policy" {
  repository = aws_ecr_repository.app_repo.name

  policy = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "최신 10개 이미지만 유지",
            "selection": {
                "tagStatus": "any",
                "countType": "imageCountMoreThan",
                "countNumber": 10
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
}
