# file: modules/ec2-ci-ml/main.tf
# Reusable module to launch hardened Windows or RHEL instances from the latest Image Builder AMI.

variable "os" {
  description = "windows or rhel"
  type        = string
}
variable "instance_type" { default = "m6i.xlarge" }
variable "subnet_id" {}
variable "security_group_ids" { type = list(string) }
variable "iam_instance_profile" {}
variable "key_name" {}
variable "root_volume_size" { default = 100 }

data "aws_ami" "latest" {
  most_recent = true
  owners      = ["self"]
  filter {
    name   = "tag:Role"
    values = ["CI-CD-ML"]
  }
  filter {
    name   = "tag:OS"
    values = [upper(var.os)]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_instance" "ci_ml" {
  ami                    = data.aws_ami.latest.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.iam_instance_profile
  key_name               = var.key_name
  monitoring             = true

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = {
    Name = "${var.os}-ci-ml-${formatdate("YYYYMMDD", timestamp())}"
    Role = "CI-CD-ML"
    OS   = upper(var.os)
  }

  lifecycle {
    ignore_changes = [ami]   # Prevent accidental replacement when new AMIs appear
  }
}
