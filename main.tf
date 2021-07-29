terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.66.0"

  cidr = var.vpc_cidr_block

  azs             = data.aws_availability_zones.available.names
  private_subnets = slice(var.private_subnet_cidr_blocks, 0, var.private_subnets_per_vpc)
  public_subnets  = slice(var.public_subnet_cidr_blocks, 0, var.public_subnets_per_vpc)

  enable_nat_gateway = true
  enable_vpn_gateway = false
}

module "app_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/web"
  version = "3.17.0"

  name        = "imply-private-sg-${var.project_name}-${var.environment}"
  description = "Security group for web-servers with HTTP ports open within VPC"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = module.vpc.public_subnets_cidr_blocks
}

module "lb_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/web"
  version = "3.17.0"

  name = "load-balancer-sg-${var.project_name}-${var.environment}"

  description = "Security group for load balancer with HTTP ports open within VPC"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
}

resource "random_string" "lb_id" {
  length  = 4
  special = false
}

module "elb_http" {
  source  = "terraform-aws-modules/elb/aws"
  version = "2.4.0"

  # Comply with ELB name restrictions 
  # https://docs.aws.amazon.com/elasticloadbalancing/2012-06-01/APIReference/API_CreateLoadBalancer.html
  name     = trimsuffix(substr(replace(join("-", ["lb", random_string.lb_id.result, var.project_name, var.environment]), "/[^a-zA-Z0-9-]/", ""), 0, 32), "-")
  internal = false

  security_groups = [module.lb_security_group.this_security_group_id]
  subnets         = module.vpc.public_subnets

  number_of_instances = 1
  instances           = [aws_instance.imply-manager.id]

  listener = [{
    instance_port     = "9097"
    instance_protocol = "HTTP"
    lb_port           = "9097"
    lb_protocol       = "HTTP"
  }]

  health_check = {
    target              = "HTTP:80/index.html"
    interval            = 10
    healthy_threshold   = 3
    unhealthy_threshold = 10
    timeout             = 5
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_key_pair" "imply_keypair" {
  key_name   = "imply-keypair"
  public_key = <<-EOF
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDsjKL/Awmz9UY1RKKKYb3xv/75oI9Vy6rMTva0Nb3VMnnnq10ipSwH7PCxtFlaagMQypp7CqQBmJqfAwJEbv3zLgWsyEX8s2ltgja1QSVtOiICAL7JE4We6znYcFZ9cIOfVv00Zx6uCCzv4a/8eGpqsHdnbANG1lCbwiBJERJqy7n+re0jhrvXPPsrHdU/oMrr3TqPlM9Y5WlNYL4jhW9PQhwhjujWLMvM15GooQgakRUWH/uGOUD5mzFscxeBKfHoLOCp9QUd+Xx4yKy0qvO8V/QNhSPxqy1h62M0ZjCAvZiWyjFzvRCBMDLsD84eDEWe6Yqx9d8g5axxTlPDHOzewmvO7edk3zTtHyZTWStRrFHSfMpleSdyDc8CRmFRkJ+3QKDyoAAhzqbwwbHgL5V7ww2fQncsrDDL872LRFEerx/w/19xnUGhmP7FpduSDbnI8FU19vKwiLbybGVyF4dfu85CqdSFj1XN2ugeZLC0r4I/ESkiIwjGtdpKwVVexnE= hellmarbecker@Hellmar-Becker.local
    EOF
}

resource "aws_instance" "imply-manager" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type["manager"]

  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [module.app_security_group.this_security_group_id]

  key_name = "imply-keypair"

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    curl -O https://static.imply.io/release/imply-manager-2021.07.tar.gz
    tar -xvf imply-manager-2021.07.tar.gz
    sudo imply-manager-2021.07/script/install
    EOF

  tags = {
    Terraform   = "true"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_instance" "imply-node" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type["node"]

  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [module.app_security_group.this_security_group_id]

  key_name = "imply-keypair"

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    curl -O https://static.imply.io/release/imply-agent-v3.tar.gz
    tar -xvf imply-agent-2021.07.tar.gz
    sudo imply-agent-2021.07/script/install
    EOF

  tags = {
    Terraform   = "true"
    Project     = var.project_name
    Environment = var.environment
  }
}

