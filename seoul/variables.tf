# ==========================================================================
# 서울 리전 — 입력 변수 정의
# 실제 값은 terraform.tfvars에 작성, .gitignore로 Git 비추적
# ==========================================================================

variable "domain" {
  type    = string
  default = "siseon.live"
}

variable "delegation_set_id" {
  type    = string
  default = "N02295603ILJ5HVTJBLTY"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "jwt_secret" {
  type      = string
  sensitive = true
}

variable "stockops_ai_service_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "ai_module_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "gemini_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "aws_access_key_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "aws_secret_access_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "vertex_ai_credentials_json" {
  type      = string
  sensitive = true
  default   = ""
}

# ID류 — 사실상 시크릿 아님. default 비워두면 미사용 시 무해
variable "bedrock_knowledge_base_id" {
  type    = string
  default = ""
}

variable "bedrock_agent_id" {
  type    = string
  default = ""
}

variable "bedrock_agent_alias_id" {
  type    = string
  default = ""
}

variable "bedrock_guardrail_id" {
  type    = string
  default = ""
}

variable "vertex_ai_project_id" {
  type    = string
  default = ""
}