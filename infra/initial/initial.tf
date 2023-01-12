terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.49"
    }
  }

  # Depends on my terraform-github-setup
  backend "s3" {
    bucket = "iwakiri.infra"
    key    = "terraform/clean_house_initial"
    region = "ap-northeast-1"
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = "ap-northeast-1"

  assume_role {
    role_arn = "arn:aws:iam::399923773482:role/TerraformGithubApplyRole"
  }
}

# lambda functionの本体をデプロイする先のS3 bucket
resource "aws_s3_bucket" "clean_house_lambdas" {
  bucket = "clean-house-lambdas"

  tags = {
    project = "clean_house"
  }
}