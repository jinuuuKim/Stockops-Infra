# ==========================================================================
# ECR 모듈 - 메인 프라이빗 저장소 및 수명주기 정책 정의 (Main)
# ==========================================================================

resource "aws_ecr_repository" "app_repo" {
  name                 = "${var.region_name}-stockops-app-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }
}

resource "aws_ecr_lifecycle_policy" "app_repo_policy" {
  repository = aws_ecr_repository.app_repo.name

  policy = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "최신 10개 이미지만 남기고 오래된 이미지는 자동 삭제하여 비용 절감",
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