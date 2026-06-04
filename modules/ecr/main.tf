# ==========================================================================
# ECR 모듈 - 메인 프라이빗 저장소 및 수명주기 정책 정의 (Main)
# ==========================================================================

resource "aws_ecr_repository" "app_repo" {
  # 🌟 [에러 해결 핵심] 고정된 이름 대신, 주입된 상용 서비스 명칭 그대로 저장소를 개설합니다.
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