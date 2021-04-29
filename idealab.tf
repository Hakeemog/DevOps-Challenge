
provider "aws" {
  region = "us-east-1"
  access_key = "AKIAXF32XMSTQTPAAW57"
  secret_key = "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"
  }

#Create a VPC
resource "aws_vpc" "prod_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
      Name -"production"
  }
}
#Create internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod_vpc.id

  }

  #Create custom route-table
  resource "aws_route_table" "prod_route_table" {
  vpc_id = aws_vpc.prod_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.gw.id

  tags = {
    Name = "prod"
  }
}
}

# Create subnet
resource "aws_subnet" "subnet-1" {
  vpc_id = aws_vpc.prod_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "prods_Subnet"
  }
}
#Associate subnet with route table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}
#Create a public security group for load balancer
resource "aws_security_group" "public_SG{
  name        = "public_SG"
  description = "Public SG for ALB"
  vpc_id      = aws_vpc.prod_vpc.id

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

 ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
   egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "ALB_SG"
  }
}

#Create a private security group for EC2 instances
resource "aws_security_group" "private_SG{
  name        = "private_SG"
  description = "Private SG for ec2 instance"
  vpc_id      = aws_vpc.prod_vpc.id

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    security_group_id      = "aws_security_group_public_SG.id
    
    egress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  }
# Create network interface with an IP in the subnet
resource "aws_network_interface" "web_server_nic" {
  subnet_id       = aws subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]
}
#Create an elastic IP to the network
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web_server_nic.id
  associate_with_private_ip = "10.0.1.50"
  depends-on                = [aws_internet_gateway.gw]
}

#Create Ubuntu server and install nginx
resource "aws_instance" "web_server_instance" {
  ami           = "ami-042e8287309f5df03" 
  instance_type = "t2.micro"
  availability_zone = "us-east-1a"
  instance_count = "2"

  Key_name = "main_key"

  network_interface {
    network_id = 0
    network_interface_id = aws_network_interface.web_server_nic.id
  }
  user_data = <<EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install nginx -y
              sudo systmctl start nginx
              EOF

  tags = {
    Name = "Web_SVR"
}

#Create Ubuntu server and install nodejs
resource "aws_instance" "app_server_instance" {
  ami           = "ami-042e8287309f5df03" 
  instance_type = "t2.micro"
  availability_zone = "us-east-1a"
  instance_count = "2"
  Key_name = "main_key"

  network_interface {
    network_id = 0
    network_interface_id = aws_network_interface.web_server_nic.id
  }
  user_data = <<EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install -y nodejs
              sudo apt install build-essential -y
              sudo systmctl start nodejs
              EOF

  tags = {
    Name = "app_SVR"
}
#Create application load balancer
resource "aws_lb" "main-lb" {
  name               = "main-lb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = aws_subnet.public.*.id 

  enable_deletion_protection = true

  access_logs {
    bucket  = aws_s3_bucket.lb_logs.bucket
    prefix  = "main-lb"
    enabled = true
  }

  tags = {
    Environment = "production"
  }
}
#Create aurora db
module "db" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "~> 3.0"

  name           = "test-aurora-db-postgres96"
  engine         = "aurora-postgresql"
  engine_version = "11.9"
  instance_type  = "db.r5.large"

  vpc_id  = "aws_vpc.prod_vpc.id"

  subnets = ["subnet-12345678", "subnet-87654321"]  

  replica_count           = 1
  allowed_security_groups = ["sg-12345678"]
  allowed_cidr_blocks     = ["10.20.0.0/20"]

  storage_encrypted   = true
  apply_immediately   = true
  monitoring_interval = 10

  db_parameter_group_name         = "default"
  db_cluster_parameter_group_name = "default"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}
