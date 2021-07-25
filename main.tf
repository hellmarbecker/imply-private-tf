terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = "us-west-2"
}

resource "aws_instance" "app_server" {
  ami                    = "ami-08d70e59c07c61a3a"
  instance_type          = "t2.micro"
  vpc_security_group_ids = ["sg-8f1097de"]
  subnet_id              = "subnet-934faad9"

  tags = {
    Name = var.instance_name
  }
}

