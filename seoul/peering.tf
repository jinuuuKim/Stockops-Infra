# ==========================================================================
# 서울 ↔ 오하이오 VPC 피어링 (크로스 리전)
# Seoul: ap-northeast-2 (10.0.0.0/16) ↔ Ohio: us-east-2 (10.1.0.0/16)
# 피어링 연결·수락·양방향 라우트 전부 Seoul state에서 관리 (ohio alias 활용)
# ==========================================================================

# ── Ohio VPC 조회 ──────────────────────────────────────────────────────────

data "aws_vpc" "ohio" {
  provider = aws.ohio
  filter {
    name   = "tag:Name"
    values = ["ohio-vpc"]
  }
}

# ── 피어링 연결 요청 (Seoul → Ohio) ───────────────────────────────────────

resource "aws_vpc_peering_connection" "seoul_to_ohio" {
  vpc_id      = module.seoul_vpc.vpc_id
  peer_vpc_id = data.aws_vpc.ohio.id
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

# ── Seoul 라우팅 테이블 → Ohio CIDR (10.1.0.0/16) ─────────────────────────
# 모듈 output 참조 → VPC 재생성 시에도 RT ID가 자동 갱신됨
# pub_rt: Grafana 등 퍼블릭 경유 트래픽 대비, priv_app_rt: 워커노드, priv_db_rt: RDS

locals {
  seoul_rt_ids = toset([
    module.seoul_vpc.pub_rt_id,
    module.seoul_vpc.priv_app_rt_id,
    module.seoul_vpc.priv_db_rt_id,
  ])
}

resource "aws_route" "seoul_to_ohio" {
  for_each = local.seoul_rt_ids

  route_table_id            = each.value
  destination_cidr_block    = "10.1.0.0/16"
  vpc_peering_connection_id = aws_vpc_peering_connection.seoul_to_ohio.id
  depends_on                = [aws_vpc_peering_connection_accepter.ohio]
}

# ── Ohio 라우팅 테이블 → Seoul CIDR (10.0.0.0/16) — 직접 ID 지정 ──────────
# rtb-0e74d86642a7e5e9f: ohio-priv-app-rt
# rtb-0c591d6d25402a829: ohio-priv-db-rt
# rtb-02632a739f7092f67: ohio-pub-rt

locals {
  ohio_private_rt_ids = toset([
    "rtb-0e74d86642a7e5e9f",
    "rtb-0c591d6d25402a829",
    "rtb-02632a739f7092f67",
  ])
}

resource "aws_route" "ohio_to_seoul" {
  for_each = local.ohio_private_rt_ids

  provider                  = aws.ohio
  route_table_id            = each.value
  destination_cidr_block    = "10.0.0.0/16"
  vpc_peering_connection_id = aws_vpc_peering_connection.seoul_to_ohio.id
  depends_on                = [aws_vpc_peering_connection_accepter.ohio]
}
