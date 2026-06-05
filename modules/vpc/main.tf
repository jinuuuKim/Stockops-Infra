# ==========================================================================
# VPC 모듈 - 메인 인프라 자원 정의 (VPC, Subnets, Gateways, Routing)
# ==========================================================================

# 1. 메인 가상 사설 네트워크 공간(VPC) 생성
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true # DNS 주소 매핑 활성화 (RDS 필수)
  enable_dns_support   = true

  tags = {
    Name = "${var.region_name}-vpc"
  }
}

# 2. 퍼블릭 서브넷 (외부 로드밸런서 및 NAT 게이트웨이 배치용)
resource "aws_subnet" "pub_sub_2a" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.pub_sub_2a_cidr
  availability_zone       = var.az_a
  map_public_ip_on_launch = true # 이 서브넷 내 자원은 자동 퍼블릭 IP 부여

  tags = {
    Name                                  = "${var.region_name}-pub-sub-2a"
    "kubernetes.io/role/elb"              = "1"
    "kubernetes.io/cluster/seoul-cluster" = "shared"
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
    "kubernetes.io/cluster/seoul-cluster" = "shared"
  }
}

# 3. 프라이빗 애플리케이션 서브넷 (ECS Fargate 백엔드 배치용)
resource "aws_subnet" "priv_app_sub_2a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.priv_app_sub_2a_cidr
  availability_zone = var.az_a

  tags = {
    Name                                  = "${var.region_name}-priv-app-2a"
    "kubernetes.io/role/internal-elb"     = "1"
    "kubernetes.io/cluster/seoul-cluster" = "shared"
  }
}

resource "aws_subnet" "priv_app_sub_2c" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.priv_app_sub_2c_cidr
  availability_zone = var.az_c

  tags = {
    Name                                  = "${var.region_name}-priv-app-2c"
    "kubernetes.io/role/internal-elb"     = "1"
    "kubernetes.io/cluster/seoul-cluster" = "shared"
  }
}

# 4. 프라이빗 데이터베이스 서브넷 (RDS PostgreSQL 배치용)
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

# 5. 인터넷 게이트웨이 (VPC의 메인 외부 대문)
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.region_name}-igw"
  }
}

# 6. NAT 게이트웨이용 고정 퍼블릭 IP (Elastic IP)
resource "aws_eip" "nat_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.this] # IGW가 먼저 생성되어야 함

  tags = {
    Name = "${var.region_name}-nat-eip"
  }
}

# 7. NAT 게이트웨이 (프라이빗 서버들의 아웃바운드 인터넷 통로)
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.pub_sub_2a.id # Public Subnet A에 상주

  tags = {
    Name = "${var.region_name}-nat-gw"
  }

  depends_on = [aws_internet_gateway.this]
}

# ==========================================================================
# 8. 라우팅 테이블 및 연결 설정 (교통 정리)
# ==========================================================================

# --- Public 라우팅: 외부 인터넷(IGW)으로 통하는 길 ---
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

# --- Private App 라우팅: 외부로 나갈 때 NAT 게이트웨이를 거치도록 설정 ---
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

# --- Private DB 라우팅: 인터넷 경로를 완전히 차단하여 격리 조치 ---
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