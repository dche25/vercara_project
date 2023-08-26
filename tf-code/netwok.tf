# VPC
resource "aws_vpc" "web_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "web-vpc"
  }
}
# Internet Gateway for Public Subnet
resource "aws_internet_gateway" "web_igw" {
  vpc_id = aws_vpc.web_vpc.id
}

# Public Subnet
resource "aws_subnet" "web_public_subnet" {
  vpc_id                  = aws_vpc.web_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = {
    Name = "web-public-subnet"
  }
}

# Add a route to the Internet Gateway for Public Subnet
resource "aws_route_table" "web_public_route_table" {
  vpc_id = aws_vpc.web_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.web_igw.id
  }
}

# Associate the public subnet with the route table
resource "aws_route_table_association" "web_public_route_table_association" {
  subnet_id      = aws_subnet.web_public_subnet.id
  route_table_id = aws_route_table.web_public_route_table.id
}

# Private Subnet
resource "aws_subnet" "web_private_subnet" {
  vpc_id                  = aws_vpc.web_vpc.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = false
  availability_zone       = "us-east-1b"
  tags = {
    Name = "web-private-subnet"
  }
}

# Allocate an Elastic IP
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

# Create NAT Gateway
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.web_public_subnet.id
}

# Create Private Subnet Route Table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.web_vpc.id
}

resource "aws_route" "private_route" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id
}

resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.web_private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Group
resource "aws_security_group" "web_sg" {
  name        = "web-sg"
  description = "Web Security Group"
  vpc_id      = aws_vpc.web_vpc.id
  // Add security group settings

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.web_vpc.cidr_block]
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
    Name = "my_web_security_group"
  }
}

# ECS required Below VPC Endpoint to connect and pull docker image from ECR service.

# VPC Endpoint for Amazon ECR API
resource "aws_vpc_endpoint" "ecr_api_endpoint" {
  vpc_id       = aws_vpc.web_vpc.id
  service_name = "com.amazonaws.us-east-1.ecr.api"
  vpc_endpoint_type = "Interface"
  subnet_ids  = [aws_subnet.web_private_subnet.id, aws_subnet.web_public_subnet.id]
  security_group_ids = [aws_security_group.web_sg.id]
}

# VPC Endpoint for Amazon ECR Docker Registry
resource "aws_vpc_endpoint" "ecr_dkr_endpoint" {
  vpc_id       = aws_vpc.web_vpc.id
  service_name = "com.amazonaws.us-east-1.ecr.dkr"
  vpc_endpoint_type = "Interface"
  subnet_ids  = [aws_subnet.web_private_subnet.id, aws_subnet.web_public_subnet.id]
  security_group_ids = [aws_security_group.web_sg.id]
}

resource "aws_vpc_endpoint" "s3_gateway_endpoint" {
  vpc_id       = aws_vpc.web_vpc.id
  service_name = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [aws_route_table.private_route_table.id,  aws_route_table.web_public_route_table.id]
}
