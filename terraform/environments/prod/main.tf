terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket         = "terraform-state-219400381702-prod"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source = "../../modules/vpc"
  
  environment = "prod"
  vpc_cidr    = "10.2.0.0/16"
  
  tags = {
    Environment = "prod"
    Project     = "ecommerce"
  }
}

module "eks" {
  source = "../../modules/eks"
  
  environment     = "prod"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  node_group_size = {
    desired = 3
    max     = 10
    min     = 3
  }
  
  tags = {
    Environment = "prod"
    Project     = "ecommerce"
  }
}