# file: imagebuilder-pipelines/main.tf
# Creates both Windows and RHEL Image Builder pipelines with shared infrastructure.
# Real-world note: Keep the recipe components minimal. Heavy ML stacks (CUDA, PyTorch, etc.) belong in a second “ML-optimized” recipe.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" { default = "us-east-1" }
variable "environment" { default = "prod" }
variable "vpc_id" {}
variable "subnet_ids" { type = list(string) }
variable "security_group_ids" { type = list(string) }

# Shared infrastructure configuration
resource "aws_imagebuilder_infrastructure_configuration" "ci_ml" {
  name                          = "ci-ml-infra-${var.environment}"
  instance_profile_name         = aws_iam_instance_profile.imagebuilder.name
  instance_types                = ["m6i.large", "m6i.xlarge", "g5.xlarge"]
  subnet_id                     = var.subnet_ids[0]
  security_group_ids            = var.security_group_ids
  terminate_instance_on_failure = true

  logging {
    s3_logs {
      s3_bucket_name = aws_s3_bucket.imagebuilder_logs.bucket
    }
  }
}

# Windows Recipe
resource "aws_imagebuilder_image_recipe" "windows" {
  name         = "windows-ci-ml-recipe"
  parent_image = "arn:aws:imagebuilder:${var.region}:aws:image/windows-server-2022-english-full-base-x86/x.x.x"
  version      = "1.0.0"

  block_device_mapping {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 100
      volume_type = "gp3"
      encrypted   = true
    }
  }

  component {
    component_arn = "arn:aws:imagebuilder:${var.region}:aws:component/update-windows/x.x.x"
  }
  component {
    component_arn = "arn:aws:imagebuilder:${var.region}:aws:component/amazon-cloudwatch-agent-windows/x.x.x"
  }
}

# RHEL Recipe
resource "aws_imagebuilder_image_recipe" "rhel" {
  name         = "rhel-ci-ml-recipe"
  parent_image = data.aws_ami.rhel9.id
  version      = "1.0.0"

  block_device_mapping {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 80
      volume_type = "gp3"
      encrypted   = true
    }
  }

  component {
    component_arn = "arn:aws:imagebuilder:${var.region}:aws:component/update-linux/x.x.x"
  }
  component {
    component_arn = "arn:aws:imagebuilder:${var.region}:aws:component/amazon-ssm-agent-linux/x.x.x"
  }
  component {
    component_arn = "arn:aws:imagebuilder:${var.region}:aws:component/amazon-cloudwatch-agent-linux/x.x.x"
  }
}

data "aws_ami" "rhel9" {
  most_recent = true
  owners      = ["309956199498"]
  filter {
    name   = "name"
    values = ["RHEL-9.*x86_64*"]
  }
}

# Pipelines
resource "aws_imagebuilder_image_pipeline" "windows" {
  name                             = "windows-ci-ml-pipeline"
  image_recipe_arn                 = aws_imagebuilder_image_recipe.windows.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.ci_ml.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.main.arn
  status                           = "ENABLED"

  schedule {
    schedule_expression = "cron(0 2 ? * SUN *)"
  }
}

resource "aws_imagebuilder_image_pipeline" "rhel" {
  name                             = "rhel-ci-ml-pipeline"
  image_recipe_arn                 = aws_imagebuilder_image_recipe.rhel.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.ci_ml.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.main.arn
  status                           = "ENABLED"

  schedule {
    schedule_expression = "cron(0 3 ? * SUN *)"
  }
}
