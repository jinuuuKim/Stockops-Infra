# ─────────────────────────────────────────────
# seoul/iam.tf
# ─────────────────────────────────────────────

module "github_oidc" {
  source = "../modules/github-oidc"

  github_org      = "jinuuuKim"
  github_repo     = "Stockops-Application"
  allowed_branches = ["main"]

  ecr_arns = [
    module.seoul_ecr["stockops-api"].repository_arn,
    module.seoul_ecr["stockops-ai"].repository_arn,
    module.seoul_ecr["stockops-admin-web"].repository_arn,
    module.seoul_ecr["stockops-client-web"].repository_arn,
  ]
}