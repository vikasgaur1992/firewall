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
  region = "us-east-1"
}

variable "ssh_key" {
  description = "Name of the SSH key pair"
  type        = string
}

#variable "bootstrap_userdata" {
#  description = "Bootstrap options for PAN-OS"
#  type        = map(string)
#}
variable "bootstrap_userdata" {
  description = "Bootstrap options for PAN-OS in key-value format"
  type        = map(string)
  default = {
    hostname                      = "vm-fw"
    "mgmt-interface-swap"        = "enable"
    "dhcp-accept-server-hostname" = "no"
    "dhcp-accept-server-domain"   = "no"
  }
}


resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "mgmt" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "dp" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
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

module "fw" {
  source  = "PaloAltoNetworks/swfw-modules/aws//modules/vmseries"
  version = "2.0.0"
  name           = "vm300-fw"
  instance_type  = "m5.xlarge"
  ssh_key_name   = var.ssh_key
  vmseries_ami_id      = "ami-0000246c645ec5f05"  # <<-- Add this line

interfaces = {
  mgmt = {
    device_index       = 0
    subnet_id          = aws_subnet.mgmt.id
    create_public_ip   = true
    source_dest_check  = true
    security_group_ids = [aws_security_group.mgmt.id]
  }
  dataplane = {
    device_index       = 1
    subnet_id          = aws_subnet.dp.id
    create_public_ip   = false
    source_dest_check  = true
    security_group_ids = []
  }
}

#  bootstrap_options = jsonencode(var.bootstrap_userdata)
bootstrap_options = <<-EOF
    hostname=vm-fw
    mgmt-interface-swap=enable
    dhcp-accept-server-hostname=no
    dhcp-accept-server-domain=no
  EOF
}
