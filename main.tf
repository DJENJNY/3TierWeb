terraform {
  backend "s3" {
    bucket = "3tier-terraform32"
    key    = "terraform"
    region = "us-east-1"
  }

required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_iam_role" "ec2_role" {
  name = "ec2_instance_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_read_only_policy" {
  
  role      = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" # Example policy
}

resource "aws_iam_role_policy_attachment" "AmazonSSM_Managed_Instance_Core" {
  
  role      = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" # Example policy
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "3tiervpc"
  }
}

resource "aws_subnet" "public" {

  count = 2

  vpc_id     = aws_vpc.main.id
  cidr_block = element(["10.0.1.0/24", "10.0.2.0/24"], count.index)

  availability_zone = element(["us-east-1a", "us-east-1b", ], count.index)

  tags = {
    Name = "subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {


  count = 2

  vpc_id     = aws_vpc.main.id
  cidr_block = element(["10.0.4.0/24", "10.0.5.0/24"], count.index)

  availability_zone = element(["us-east-1a", "us-east-1b", ], count.index)


  tags = {
    Name = "subnet-${count.index + 1}"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main"
  }
}

resource "aws_eip" "nat_eip" {
  count  = 2
  domain = "vpc"

  depends_on = [aws_internet_gateway.gw]
}

resource "aws_nat_gateway" "ngw" {
  count         = 2
  allocation_id = aws_eip.nat_eip[count.index].id
  subnet_id     = element(aws_subnet.public[*].id, count.index)

  tags = {
    Name = "gw-NAT-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.gw]
}

resource "aws_route_table" "pubrt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "public route table"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = element(aws_subnet.public[*].id, count.index)
  route_table_id = aws_route_table.pubrt.id
}

resource "aws_route_table" "private" {
  count = 2

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw[count.index].id
  }

  tags = {
    Name = "private-rtable-${count.index +1}"
  }
}

resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "allow_tls"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv4" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls_ssh" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index)
}

resource "aws_security_group" "external_lb" {
  name        = "external_lb"
  description = "External Load balancer security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "external_lb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "external_lb" {
  security_group_id = aws_security_group.external_lb.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  ip_protocol = "tcp"
  to_port     = 80
}

resource "aws_security_group" "web_tier" {
  name        = "web_tier"
  description = "Web tier instance security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "web_tier"
  }
}

resource "aws_vpc_security_group_ingress_rule" "web_tier" {
  security_group_id = aws_security_group.web_tier.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_security_group_rule" "lb_to_instance" {
  type                     = "ingress"                      # Or "egress"
  security_group_id        = aws_security_group.web_tier.id # The security group to apply the rule to
  from_port                = 80                             # Replace with the port you want to allow
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.external_lb.id # The security group to allow traffic from
}

resource "aws_security_group" "internal_lb" {
  name        = "internal_lb"
  description = "internal lb instance security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "internal lb security group"
  }
}

resource "aws_security_group_rule" "allow_web_to_lb" {
  type                     = "ingress"                         # Or "egress"
  security_group_id        = aws_security_group.internal_lb.id # The security group to apply the rule to
  from_port                = 80                                # Replace with the port you want to allow
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.web_tier.id # The security group to allow traffic from
}

resource "aws_security_group" "private_instances" {
  name        = "private_instances"
  description = "private instance security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "private instance security group"
  }
}

resource "aws_security_group_rule" "allow_lb_to_private_instance" {
  type                     = "ingress"                               # Or "egress"
  security_group_id        = aws_security_group.private_instances.id # The security group to apply the rule to
  from_port                = 4000                                    # Replace with the port you want to allow
  to_port                  = 4000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.internal_lb.id # The security group to allow traffic from
}

resource "aws_vpc_security_group_ingress_rule" "private_instance" {
  security_group_id = aws_security_group.private_instances.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 4000
  ip_protocol       = "tcp"
  to_port           = 4000
}

resource "aws_security_group" "database" {
  name        = "database"
  description = "database"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "database"
  }
}

resource "aws_security_group_rule" "database" {
  type                     = "ingress"                      # Or "egress"
  security_group_id        = aws_security_group.database.id # The security group to apply the rule to
  from_port                = 3306                           # Replace with the port you want to allow
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.private_instances.id # The security group to allow traffic from
}

resource "aws_instance" "app_tier" {
  count = 1
  ami                         = "ami-071226ecf16aa7d96" # Replace with your desired AMI ID
  instance_type               = "t2.micro" # Or your desired instance type
  key_name                    = "EC2 Tutorial" # Replace with your key pair name
  vpc_security_group_ids      = [aws_security_group.allow_tls.id] # Replace with your security group ID
  subnet_id                   = element(aws_subnet.public.*.id, count.index)
  associate_public_ip_address = true # Replace with your subnet ID
  tags = {
    Name = "app_instance" # Optional: Add tags for easier identification
  }
}

output "instance_public_ip" {
  value = aws_instance.app_tier[*].public_ip
}















