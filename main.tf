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

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "3tiervpc"
  }
}


resource "aws_subnet" "public" {

  count = 3

  vpc_id     = aws_vpc.main.id
  cidr_block = element(["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"], count.index)

  availability_zone = element(["us-east-1a", "us-east-1b",], count.index)

  # tags = {
  #   Name = "subnet 1"
  # }
}

resource "aws_subnet" "private" {

  
  count = 3

  vpc_id     = aws_vpc.main.id
  cidr_block = element(["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"], count.index)

  availability_zone = element(["us-east-1a", "us-east-1b",], count.index)


  # tags = {
  #   Name = "subnet 1"
  # }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main"
  }
}

resource "aws_eip" "nat_eip" {
  count = 2
  domain = "vpc"

  depends_on                = [aws_internet_gateway.gw]
}

resource "aws_nat_gateway" "ngw" {
  count = 2
  allocation_id = aws_eip.nat_eip[count.index].id
  subnet_id     = element(aws_subnet.public[*].id, count.index)

  tags = {
    Name = "gw NAT"
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
    Name = "example"
  }
}

resource "aws_route_table_association" "public" {
  count = 2
  subnet_id      = element(aws_subnet.public[*].id, count.index)
  route_table_id = aws_route_table.pubrt.id
}

# resource "aws_route_table" "private" {
#   vpc_id = aws_vpc.main.id

#   route {
#     cidr_block = "0.0.0.0/0"
#     gateway_id = aws_nat_gateway.ngw.id
#   }

#   tags = {
#     Name = "example"
#   }
# }

# resource "aws_route_table_association" "private" {
#   count = 2

#   subnet_id      = element(aws_subnet.public[*].id, count.index)
#   route_table_id = aws_route_table.pubrt.id
# }



