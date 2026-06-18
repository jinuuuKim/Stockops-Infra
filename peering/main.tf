# ==========================================================================
# 서울 ↔ 오하이오 VPC 피어링 (크로스 리전)
# Seoul: ap-northeast-2 (10.0.0.0/16) ↔ Ohio: us-east-2 (10.1.0.0/16)
#
# Seoul/Ohio state를 terraform_remote_state로 읽어 VPC ID·RT ID를 참조.
# 하드코딩 없이 VPC 재생성 시 자동 갱신. 순환 참조 없음.
# Apply 순서: seoul → ohio → peering
# Destroy 순서: peering → ohio → seoul
# ==========================================================================

data "terraform_remote_state" "seoul" {
  backend = "s3"
  config = {
    bucket  = "siseon-terraform-state"
    key     = "infra/seoul/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "siseon"
  }
}

data "terraform_remote_state" "ohio" {
  backend = "s3"
  config = {
    bucket  = "siseon-terraform-state"
    key     = "infra/ohio/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "siseon"
  }
}

locals {
  seoul_rt_ids = toset([
    data.terraform_remote_state.seoul.outputs.pub_rt_id,
    data.terraform_remote_state.seoul.outputs.priv_app_rt_id,
    data.terraform_remote_state.seoul.outputs.priv_db_rt_id,
  ])

  ohio_rt_ids = toset([
    data.terraform_remote_state.ohio.outputs.pub_rt_id,
    data.terraform_remote_state.ohio.outputs.priv_app_rt_id,
    data.terraform_remote_state.ohio.outputs.priv_db_rt_id,
  ])
}

# ── 피어링 연결 요청 (Seoul → Ohio) ───────────────────────────────────────

resource "aws_vpc_peering_connection" "seoul_to_ohio" {
  vpc_id      = data.terraform_remote_state.seoul.outputs.vpc_id
  peer_vpc_id = data.terraform_remote_state.ohio.outputs.vpc_id
  peer_region = "us-east-2"
  auto_accept = false

  tags = {
    Name = "seoul-ohio-peering"
    Side = "requester"
  }
}

# ── 피어링 수락 (Ohio 측) ──────────────────────────────────────────────────

resource "aws_vpc_peering_connection_accepter" "ohio" {
  provider                  = aws.ohio
  vpc_peering_connection_id = aws_vpc_peering_connection.seoul_to_ohio.id
  auto_accept               = true

  tags = {
    Name = "seoul-ohio-peering"
    Side = "accepter"
  }
}

# ── DNS 해석 활성화 (양방향) ──────────────────────────────────────────────

resource "aws_vpc_peering_connection_options" "seoul" {
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.ohio.id

  requester {
    allow_remote_vpc_dns_resolution = true
  }

  depends_on = [aws_vpc_peering_connection_accepter.ohio]
}

resource "aws_vpc_peering_connection_options" "ohio" {
  provider                  = aws.ohio
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.ohio.id

  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  depends_on = [aws_vpc_peering_connection_accepter.ohio]
}

# ── Seoul 라우팅 테이블 → Ohio CIDR ───────────────────────────────────────

resource "aws_route" "seoul_to_ohio" {
  for_each = local.seoul_rt_ids

  route_table_id            = each.value
  destination_cidr_block    = "10.1.0.0/16"
  vpc_peering_connection_id = aws_vpc_peering_connection.seoul_to_ohio.id
  depends_on                = [aws_vpc_peering_connection_accepter.ohio]
}

# ── Ohio 라우팅 테이블 → Seoul CIDR ───────────────────────────────────────

resource "aws_route" "ohio_to_seoul" {
  for_each = local.ohio_rt_ids

  provider                  = aws.ohio
  route_table_id            = each.value
  destination_cidr_block    = "10.0.0.0/16"
  vpc_peering_connection_id = aws_vpc_peering_connection.seoul_to_ohio.id
  depends_on                = [aws_vpc_peering_connection_accepter.ohio]
}
