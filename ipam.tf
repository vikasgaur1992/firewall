# -----------------------------
# Terraform Provider Setup
# -----------------------------
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.16.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  default = "us-east-2"
}

variable "ssh_key_name" {
  default = "ltimeast2"
}

variable "ssh_public_key" {
  description = "Your SSH public key content"
  default     = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCm/UayXiKeg/DLYmJWj4aR8SXkfDqP48p24L41Dv63C4KyLzm2+6DiLamifXLjlsQ3tgRu3QUCm1umE5RQjVnjjredLJrwcXg2KKts+GFRJaz00nMVvlzwOUvmRBCvms/BSrZRqfzeHqdg26Udzsae7u24ZCOhMd/v/2V5yIg9u4GoSo1E35RzsqnlGDLlx/9iaRk45KdeWQnsx79l+M6hwt/AE4+IsToqLR3qHHGEYoUh1LguO8qoZ1ZwEFZc4WyFXi211LlKAlW+dljFbxRbh17nRU4oe7/xdCwmVNGvo7V22Knj6newWTpyuMEjxOOsLq44TUbFwSAtzJt/jd7B"
}

# -----------------------------
# VPC Module with IPAM
# -----------------------------
module "Security_Palo_vpc_ue1" {
  source  = "aws-ia/vpc/aws"
  version = "4.5.0"

  name                     = "Security-Paloalto-UE1"
  azs                      = ["us-east-2a", "us-east-2b"]
  vpc_ipv4_ipam_pool_id   = "ipam-pool-0993fca781102d440"
  vpc_ipv4_netmask_length = 24
  vpc_enable_dns_support   = true
  vpc_enable_dns_hostnames = true

  subnets = {
    mgmt = {
      name_prefix             = "Mgmt"
      netmask                 = 27
      connect_to_igw          = true
      connect_to_public_natgw = false
    }
    private = {
      name_prefix             = "Private"
      netmask                 = 27
      connect_to_public_natgw = false
    }
    public = {
      name_prefix               = "Public"
      netmask                   = 27
      map_public_ip_on_launch   = true
      nat_gateway_configuration = "none"
    }
  }

  vpc_flow_logs = {
    log_destination_type = "cloud-watch-logs"
    retention_in_days    = 7
  }
}

# -----------------------------
# Security Group for Management
# -----------------------------
module "Paloalto-mgmt-ue1" {
  source      = "terraform-aws-modules/security-group/aws"
  name        = "Paloalto-mgmt"
  description = "Management SG"
  vpc_id      = module.Security_Palo_vpc_ue1.vpc_attributes.id

  ingress_with_cidr_blocks = [
    {
      rule        = "ssh-tcp"
      cidr_blocks = "172.16.0.0/12"
    },
    {
      rule        = "ssh-tcp"
      cidr_blocks = "10.0.0.0/8"
    },
    {
      from_port   = 161
      to_port     = 161
      protocol    = "udp"
      cidr_blocks = "10.0.0.0/8"
    },
    {
      from_port   = 161
      to_port     = 161
      protocol    = "udp"
      cidr_blocks = "172.16.0.0/12"
    }
  ]
}

# -----------------------------
# Palo Alto AMI
# -----------------------------
data "aws_ami" "pan_fw" {
  most_recent = true
  owners      = ["aws-marketplace"]

  filter {
    name   = "name"
    values = ["PA-VM-AWS-11.2*"]
  }
}

# -----------------------------
# Bootstrap S3 Configuration
# -----------------------------
resource "aws_s3_bucket" "bootstrap_bucket" {
  bucket        = "paloalto-bootstrap-bucket-ue1"
  force_destroy = true
}

resource "aws_s3_object" "init_cfg" {
  bucket  = aws_s3_bucket.bootstrap_bucket.id
  key     = "config/init-cfg.txt"
  content = <<EOT
hostname=vmseries
auth-key-pub=${var.ssh_public_key}
management-interface-swap=yes
EOT
}

# -----------------------------
# Palo Alto VM-Series Instances
# -----------------------------
resource "aws_instance" "vmseries01" {
  ami                         = data.aws_ami.pan_fw.id
  instance_type               = "c6in.2xlarge"
  subnet_id                   = module.Security_Palo_vpc_ue1.private_subnet_attributes_by_az["us-east-2a"].id
  vpc_security_group_ids      = [module.Paloalto-mgmt-ue1.security_group_id]
  key_name                    = var.ssh_key_name
  associate_public_ip_address = true
  user_data                   = <<EOF
vmseries-bootstrap-bucket=${aws_s3_bucket.bootstrap_bucket.bucket}
hostname=PaloN/S/E/W_01
auth-key-pub=${var.ssh_public_key}
management-interface-swap=yes
bootstrap-xml-uri=s3://${aws_s3_bucket.bootstrap_bucket.bucket}/config.xml
EOF
  tags = {
    Name = "PaloN/S/E/W_01"
  }
}

resource "aws_instance" "vmseries02" {
  ami                         = data.aws_ami.pan_fw.id
  instance_type               = "c6in.2xlarge"
  subnet_id                   = module.Security_Palo_vpc_ue1.private_subnet_attributes_by_az["us-east-2b"].id
  vpc_security_group_ids      = [module.Paloalto-mgmt-ue1.security_group_id]
  key_name                    = var.ssh_key_name
  associate_public_ip_address = true
  user_data                   = <<EOF
vmseries-bootstrap-bucket=${aws_s3_bucket.bootstrap_bucket.bucket}
hostname=PaloN/S/E/W_02
auth-key-pub=${var.ssh_public_key}
management-interface-swap=yes
bootstrap-xml-uri=s3://${aws_s3_bucket.bootstrap_bucket.bucket}/config.xml
EOF
  tags = {
    Name = "PaloN/S/E/W_02"
  }
}

# -----------------------------
# Gateway Load Balancer (GWLB)
# -----------------------------
resource "aws_lb" "gwlb" {
  name               = "palo-gwlb"
  internal           = true
  load_balancer_type = "gateway"
  subnets = [
    module.Security_Palo_vpc_ue1.private_subnet_attributes_by_az["us-east-2a"].id,
    module.Security_Palo_vpc_ue1.private_subnet_attributes_by_az["us-east-2b"].id
  ]

  tags = { Name = "Palo-GWLB" }
}

resource "aws_lb_target_group" "gwlb_tg" {
  name        = "palo-gwlb-tg"
  port        = 6081
  protocol    = "GENEVE"
  vpc_id      = module.Security_Palo_vpc_ue1.vpc_attributes.id
  target_type = "instance"

  health_check {
    protocol = "TCP"
    port     = "80"
  }

  tags = { Name = "Palo-GWLB-TG" }
}

resource "aws_lb_target_group_attachment" "attach01" {
  target_group_arn = aws_lb_target_group.gwlb_tg.arn
  target_id        = aws_instance.vmseries01.id
}

resource "aws_lb_target_group_attachment" "attach02" {
  target_group_arn = aws_lb_target_group.gwlb_tg.arn
  target_id        = aws_instance.vmseries02.id
}

# -----------------------------
# VPC Endpoint Service for GWLB
# -----------------------------
resource "aws_vpc_endpoint_service" "gwlb_service" {
  acceptance_required         = false
  gateway_load_balancer_arns = [aws_lb.gwlb.arn]

  tags = { Name = "Palo-GWLB-Service" }
}
