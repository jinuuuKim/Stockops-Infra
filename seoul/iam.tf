# ==========================================================================
# 서울 리전 — IAM (GitHub Actions OIDC)
# ==========================================================================

module "github_oidc" {
  source = "../modules/github-oidc"

  github_org       = "jinuuuKim"
  github_repo      = "Stockops-Application"
  allowed_branches = ["main"]

  ecr_arns = [
    module.seoul_ecr["stockops-api"].repository_arn,
    module.seoul_ecr["stockops-ai"].repository_arn,

    # ohio — 다른 state라 직접 참조 불가 → ARN 하드코딩
    "arn:aws:ecr:us-east-2:448768137813:repository/stockops-api",
    "arn:aws:ecr:us-east-2:448768137813:repository/stockops-ai",
  ]
}
