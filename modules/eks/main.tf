# ==========================================================================
# EKS 모듈 — 클러스터, 노드 그룹, OIDC, LBC IAM
# ==========================================================================

# EKS 컨트롤 플레인 IAM Role
resource "aws_iam_role" "cluster_role" {
  name = "${var.region_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster_role.name
}

# EKS 클러스터
resource "aws_eks_cluster" "this" {
  name     = "${var.region_name}-cluster"
  version  = "1.30"
  role_arn = aws_iam_role.cluster_role.arn

  vpc_config {
    subnet_ids              = var.priv_app_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

# 워커 노드 IAM Role
resource "aws_iam_role" "node_role" {
  name = "${var.region_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_role.name
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_role.name
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_role.name
}

# app-sg → EKS 클러스터 SG 인바운드 허용
resource "aws_security_group_rule" "eks_ingress_from_app_sg" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  source_security_group_id = var.app_sg_id
}

# EKS 클러스터 SG → RDS SG 5432 허용
resource "aws_security_group_rule" "db_ingress_from_eks" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = var.db_sg_id
  source_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

# 관리형 노드 그룹
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.region_name}-managed-node-group"
  node_role_arn   = aws_iam_role.node_role.arn
  subnet_ids      = var.priv_app_subnet_ids
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]
}

# OIDC Provider (IRSA용)
data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

# AWS Load Balancer Controller IAM Role (IRSA)
data "aws_iam_policy_document" "lbc_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_policy" "lbc" {
  name   = "${var.region_name}-lbc-policy"
  policy = file("${path.module}/lbc-iam-policy.json")
}

resource "aws_iam_role" "lbc" {
  name               = "${var.region_name}-lbc-role"
  assume_role_policy = data.aws_iam_policy_document.lbc_assume.json
}

resource "aws_iam_role_policy_attachment" "lbc" {
  policy_arn = aws_iam_policy.lbc.arn
  role       = aws_iam_role.lbc.name
}
