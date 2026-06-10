# ==========================================================================
# VPC 모듈 — 네트워크 인프라 (VPC, 서브넷, 게이트웨이, 라우팅)
# ==========================================================================

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.region_name}-vpc"
  }
}

# 퍼블릭 서브넷 (ALB, NAT Gateway)
resource "aws_subnet" "pub_sub_2a" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.pub_sub_2a_cidr
  availability_zone       = var.az_a
  map_public_ip_on_launch = true

  tags = {
    Name                                  = "${var.region_name}-pub-sub-2a"
    "kubernetes.io/role/elb"              = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "pub_sub_2c" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.pub_sub_2c_cidr
  availability_zone       = var.az_c
  map_public_ip_on_launch = true

  tags = {
    Name                                  = "${var.region_name}-pub-sub-2c"
    "kubernetes.io/role/elb"              = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# 프라이빗 앱 서브넷 (EKS 워커 노드)
resource "aws_subnet" "priv_app_sub_2a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.priv_app_sub_2a_cidr
  availability_zone = var.az_a

  tags = {
    Name                                  = "${var.region_name}-priv-app-2a"
    "kubernetes.io/role/internal-elb"     = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "karpenter.sh/discovery"                    = var.cluster_name
  }
}

resource "aws_subnet" "priv_app_sub_2c" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.priv_app_sub_2c_cidr
  availability_zone = var.az_c

  tags = {
    Name                                  = "${var.region_name}-priv-app-2c"
    "kubernetes.io/role/internal-elb"     = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "karpenter.sh/discovery"                    = var.cluster_name
  }
}

# 프라이빗 DB 서브넷 (RDS)
resource "aws_subnet" "priv_db_sub_2a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.priv_db_sub_2a_cidr
  availability_zone = var.az_a

  tags = {
    Name = "${var.region_name}-priv-db-2a"
  }
}

resource "aws_subnet" "priv_db_sub_2c" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.priv_db_sub_2c_cidr
  availability_zone = var.az_c

  tags = {
    Name = "${var.region_name}-priv-db-2c"
  }
}

# 인터넷 게이트웨이
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.region_name}-igw"
  }
}

# NAT Gateway용 Elastic IP
resource "aws_eip" "nat_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.this]

  tags = {
    Name = "${var.region_name}-nat-eip"
  }
}

# NAT Gateway (프라이빗 서브넷 아웃바운드용)
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.pub_sub_2a.id
  depends_on    = [aws_internet_gateway.this]

  tags = {
    Name = "${var.region_name}-nat-gw"
  }
}

# 퍼블릭 라우팅 테이블 (IGW로 전달)
resource "aws_route_table" "pub_rt" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.region_name}-pub-rt"
  }
}

resource "aws_route_table_association" "pub_2a" {
  subnet_id      = aws_subnet.pub_sub_2a.id
  route_table_id = aws_route_table.pub_rt.id
}

resource "aws_route_table_association" "pub_2c" {
  subnet_id      = aws_subnet.pub_sub_2c.id
  route_table_id = aws_route_table.pub_rt.id
}

# 프라이빗 앱 라우팅 테이블 (NAT Gateway로 전달)
resource "aws_route_table" "priv_app_rt" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "${var.region_name}-priv-app-rt"
  }
}

resource "aws_route_table_association" "priv_app_2a" {
  subnet_id      = aws_subnet.priv_app_sub_2a.id
  route_table_id = aws_route_table.priv_app_rt.id
}

resource "aws_route_table_association" "priv_app_2c" {
  subnet_id      = aws_subnet.priv_app_sub_2c.id
  route_table_id = aws_route_table.priv_app_rt.id
}

# 프라이빗 DB 라우팅 테이블 (인터넷 경로 없음, 격리)
resource "aws_route_table" "priv_db_rt" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.region_name}-priv-db-rt"
  }
}

resource "aws_route_table_association" "priv_db_2a" {
  subnet_id      = aws_subnet.priv_db_sub_2a.id
  route_table_id = aws_route_table.priv_db_rt.id
}

resource "aws_route_table_association" "priv_db_2c" {
  subnet_id      = aws_subnet.priv_db_sub_2c.id
  route_table_id = aws_route_table.priv_db_rt.id
}
