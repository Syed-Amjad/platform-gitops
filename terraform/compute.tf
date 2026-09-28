resource "aws_key_pair" "node" {
  key_name   = "${var.name}-key"
  public_key = file(pathexpand(var.public_key_path))

  tags = {
    Name = "${var.name}-key"
  }
}

resource "aws_instance" "node" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.node.id
  vpc_security_group_ids      = [aws_security_group.node.id]
  key_name                    = aws_key_pair.node.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true

    # The volume goes when the instance goes. This is a rebuildable lab box and
    # an orphaned 40 GB volume bills at ~$3.20/month for nothing — exactly the
    # kind of leak `terraform destroy` exists to prevent.
    delete_on_termination = true
  }

  # IMDSv2 required, not optional. The v1 endpoint is reachable by anything that
  # can make an HTTP request from inside a pod, which turns any SSRF into a
  # credential read. Enforcing v2 costs nothing and is the single highest-value
  # EC2 hardening flag there is.
  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  # No Elastic IP on purpose. An EIP bills while it is NOT attached, which is
  # precisely when you have forgotten about it. The public IP changes if the
  # instance is stopped and started, and `terraform output` reports the current
  # one — that is a smaller problem than a silent charge.

  tags = {
    Name = var.name
  }

  # Terraform would otherwise be free to build the instance in parallel with the
  # route table association. The instance would come up, cloud-init would run
  # apt against a subnet with no egress yet, and the boot would fail in a way
  # that looks nothing like a race.
  depends_on = [aws_route_table_association.node]

  lifecycle {
    # The AMI data source resolves "most recent", so Ubuntu republishing would
    # otherwise show up as a plan that destroys the cluster you spent a day
    # building. Changing instance type or disk size still works; only an AMI
    # drift is ignored.
    ignore_changes = [ami]
  }
}
