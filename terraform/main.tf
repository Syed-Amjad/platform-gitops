# Lookups only — nothing here creates anything.
#
# This project needs ONE box. The previous portfolio project (ha-web-platform)
# built a multi-AZ VPC with an ALB and ACM because high availability was the
# point of it. Here the point is the delivery platform running on the node, so a
# bespoke VPC would be ceremony that adds failure modes and teaches the reader
# nothing. The default VPC is reused — but see network.tf, because reusing it
# turned out not to mean trusting it.

data "aws_vpc" "default" {
  default = true
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Canonical's account. Resolved at plan time rather than hardcoded, because a
# hardcoded AMI id is region-locked and goes stale the moment Ubuntu republishes.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Auto-detects the caller's public address so the security group can be a /32.
# Overridden by var.allowed_ssh_cidr when set — on a changing home connection,
# re-running apply is enough to correct the rule.
data "http" "my_ip" {
  count = var.allowed_ssh_cidr == null ? 1 : 0
  url   = "https://checkip.amazonaws.com"
}

locals {
  ssh_cidr = var.allowed_ssh_cidr != null ? var.allowed_ssh_cidr : "${chomp(data.http.my_ip[0].response_body)}/32"
  az       = var.availability_zone != null ? var.availability_zone : data.aws_availability_zones.available.names[0]
}
