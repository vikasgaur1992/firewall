# -----------------------------
# VARIABLES
# -----------------------------
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

variable "azs" {
  default = ["us-east-2a", "us-east-2b"]
}

provider "aws" {
  region = var.region
}

# -----------------------------
# NETWORKING
# -----------------------------
resource "aws_vpc" "security" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "Security-VPC"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.security.id
  tags = {
    Name = "Security-IGW"
  }
}

resource "aws_subnet" "mgmt_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.security.id
  cidr_block              = cidrsubnet("10.10.1.0/24", 4, count.index)
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "MGMT-${var.azs[count.index]}"
  }
}

resource "aws_subnet" "dp_subnet" {
  count             = 2
  vpc_id            = aws_vpc.security.id
  cidr_block        = cidrsubnet("10.10.2.0/24", 4, count.index)
  availability_zone = var.azs[count.index]
  tags = {
    Name = "DP-${var.azs[count.index]}"
  }
}

resource "aws_route_table" "mgmt_rt" {
  vpc_id = aws_vpc.security.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "MGMT-RT"
  }
}

resource "aws_route_table_association" "mgmt_assoc" {
  count          = 2
  subnet_id      = aws_subnet.mgmt_subnet[count.index].id
  route_table_id = aws_route_table.mgmt_rt.id
}

# -----------------------------
# SECURITY GROUPS
# -----------------------------
resource "aws_security_group" "mgmt_sg" {
  name        = "fw-mgmt-sg"
  vpc_id      = aws_vpc.security.id
  description = "Allow SSH and HTTPS"

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

  tags = {
    Name = "FW-MGMT-SG"
  }
}

resource "aws_security_group" "dp_sg" {
  name        = "fw-dp-sg"
  vpc_id      = aws_vpc.security.id
  description = "Allow all traffic (data plane)"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "FW-DP-SG"
  }
}

# -----------------------------
# GATEWAY LOAD BALANCER
# -----------------------------
resource "aws_lb" "gwlb" {
  name               = "gwlb-fw"
  load_balancer_type = "gateway"
  subnets            = aws_subnet.dp_subnet[*].id
  tags = {
    Name = "GWLB-FW"
  }
}

resource "aws_lb_target_group" "gwlb_tg" {
  name        = "gwlb-fw-tg"
  port        = 6081
  protocol    = "GENEVE"
  target_type = "instance"
  vpc_id      = aws_vpc.security.id
}

resource "aws_vpc_endpoint_service" "gwlb_service" {
  acceptance_required          = false
  gateway_load_balancer_arns  = [aws_lb.gwlb.arn]
  tags = {
    Name = "GWLB-Service"
  }
}

# -----------------------------
# VM-SERIES INSTANCES (with SSH enabled)
# -----------------------------
data "aws_ami" "pan_fw" {
  most_recent = true
  owners      = ["aws-marketplace"]
  filter {
    name   = "name"
    values = ["PA-VM-AWS-10.2*"]
  }
}

resource "aws_instance" "vmseries_01" {
  ami                    = data.aws_ami.pan_fw.id
  instance_type          = "m5.large"
  subnet_id              = aws_subnet.mgmt_subnet[0].id
  vpc_security_group_ids = [aws_security_group.mgmt_sg.id]
  key_name               = var.ssh_key_name
  associate_public_ip_address = true

  user_data = <<EOF
hostname=vmseries-01
auth-key-pub=${var.ssh_public_key}
EOF

  tags = {
    Name = "VMSeries-01"
  }
}

resource "aws_instance" "vmseries_02" {
  ami                    = data.aws_ami.pan_fw.id
  instance_type          = "m5.large"
  subnet_id              = aws_subnet.mgmt_subnet[1].id
  vpc_security_group_ids = [aws_security_group.mgmt_sg.id]
  key_name               = var.ssh_key_name
  associate_public_ip_address = true

  user_data = <<EOF
hostname=vmseries-02
auth-key-pub=${var.ssh_public_key}
EOF

  tags = {
    Name = "VMSeries-02"
  }
}

resource "aws_lb_target_group_attachment" "vm_01_attach" {
  target_group_arn = aws_lb_target_group.gwlb_tg.arn
  target_id        = aws_instance.vmseries_01.id
}

resource "aws_lb_target_group_attachment" "vm_02_attach" {
  target_group_arn = aws_lb_target_group.gwlb_tg.arn
  target_id        = aws_instance.vmseries_02.id
}