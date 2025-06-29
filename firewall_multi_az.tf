terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.3"
}

provider "aws" {
  region = "us-east-2"
}

variable "ssh_key" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "bootstrap_userdata" {
  description = "Bootstrap options for PAN-OS in key-value format"
  type        = map(string)
  default = {
    hostname                       = "vm-fw"
    "mgmt-interface-swap"         = "enable"
    "dhcp-accept-server-hostname" = "no"
    "dhcp-accept-server-domain"   = "no"
  }
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Subnets for AZ1
resource "aws_subnet" "mgmt_az1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.11.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "dp_az1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "us-east-2a"
}

# Subnets for AZ2
resource "aws_subnet" "mgmt_az2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.21.0/24"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "dp_az2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.22.0/24"
  availability_zone = "us-east-2b"
}

resource "aws_security_group" "mgmt" {
  name        = "vmseries-mgmt-sg"
  description = "Allow SSH and HTTPS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "main-igw" }
}

# Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# Route Table Associations
resource "aws_route_table_association" "mgmt_az1_rt" {
  subnet_id      = aws_subnet.mgmt_az1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "dp_az1_rt" {
  subnet_id      = aws_subnet.dp_az1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "mgmt_az2_rt" {
  subnet_id      = aws_subnet.mgmt_az2.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "dp_az2_rt" {
  subnet_id      = aws_subnet.dp_az2.id
  route_table_id = aws_route_table.public_rt.id
}

# Firewall Module for AZ1
module "fw_az1" {
  source           = "PaloAltoNetworks/swfw-modules/aws//modules/vmseries"
  version          = "2.0.0"
  name             = "vm300-fw-az1"
  instance_type    = "m5.xlarge"
  ssh_key_name     = var.ssh_key
  vmseries_ami_id  = "ami-097a8a37770dc20f6"

  interfaces = {
    mgmt = {
      device_index       = 0
      subnet_id          = aws_subnet.mgmt_az1.id
      create_public_ip   = true
      source_dest_check  = true
      security_group_ids = [aws_security_group.mgmt.id]
    }
    dataplane = {
      device_index       = 1
      subnet_id          = aws_subnet.dp_az1.id
      create_public_ip   = false
      source_dest_check  = false
      security_group_ids = []
    }
  }

  bootstrap_options = ""
}

# Firewall Module for AZ2
module "fw_az2" {
  source           = "PaloAltoNetworks/swfw-modules/aws//modules/vmseries"
  version          = "2.0.0"
  name             = "vm300-fw-az2"
  instance_type    = "m5.xlarge"
  ssh_key_name     = var.ssh_key
  vmseries_ami_id  = "ami-097a8a37770dc20f6"

  interfaces = {
    mgmt = {
      device_index       = 0
      subnet_id          = aws_subnet.mgmt_az2.id
      create_public_ip   = true
      source_dest_check  = true
      security_group_ids = [aws_security_group.mgmt.id]
    }
    dataplane = {
      device_index       = 1
      subnet_id          = aws_subnet.dp_az2.id
      create_public_ip   = false
      source_dest_check  = false
      security_group_ids = []
    }
  }

  bootstrap_options = ""
}