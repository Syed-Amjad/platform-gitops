# The subnet and its route to the internet, declared rather than discovered.
#
# ---------------------------------------------------------------------------
# WHY THIS FILE EXISTS — a defect found by running the plan, not by reading it.
#
# The original version of this stack did the obvious thing: look up the default
# VPC's subnets with a data source and drop the instance in the first one. The
# plan failed with "the collection has no elements", and the investigation found
# that this account's default VPC had been stripped at some point:
#
#   * all six default subnets  — deleted
#   * the internet gateway     — deleted
#   * the main route table     — still carrying 0.0.0.0/0 to the dead IGW,
#                                in state "blackhole"
#
# That last one is the dangerous part. A blackhole route is not an error. Had
# this stack created a subnet and let it inherit the main route table, the
# instance would have booted perfectly, reported healthy, and then hung on
# `apt-get update` and every image pull — a failure that reads like a broken
# k3s install rather than a missing gateway.
#
# So the network is declared here. Four small resources buy two things: the
# stack no longer depends on account state nobody is maintaining, and
# `terraform destroy` removes every part of it.
# ---------------------------------------------------------------------------

resource "aws_internet_gateway" "igw" {
  vpc_id = data.aws_vpc.default.id

  tags = {
    Name = "${var.name}-igw"
  }
}

resource "aws_subnet" "node" {
  vpc_id            = data.aws_vpc.default.id
  cidr_block        = var.subnet_cidr
  availability_zone = local.az

  # The node needs a routable address: SSH in, and image pulls out.
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-subnet"
  }
}

# A route table of our own, deliberately NOT the VPC's main one. The main table
# still holds the blackhole route described above; it belongs to the account
# rather than to this project, and quietly rewriting it would be a side effect
# reaching outside what this stack claims to own.
resource "aws_route_table" "public" {
  vpc_id = data.aws_vpc.default.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.name}-rt"
  }
}

resource "aws_route_table_association" "node" {
  subnet_id      = aws_subnet.node.id
  route_table_id = aws_route_table.public.id
}
