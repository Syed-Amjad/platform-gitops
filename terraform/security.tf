# One ingress rule, and it is not an accident that there is only one.
#
# ArgoCD, Grafana, Prometheus, Alertmanager and Kiali all run on this box, and
# none of them is exposed. They are reached over an SSH tunnel:
#
#   ssh -L 8080:localhost:8080 -L 3000:localhost:3000 -L 9090:localhost:9090 \
#       -L 9093:localhost:9093 -L 20001:localhost:20001 ubuntu@<ip>
#
# That is the whole reason no 8080/3000/9090 rule appears below. An ArgoCD with
# a default password and a Vault holding a root token are not things to put on
# the public internet for the convenience of not typing an ssh flag.

resource "aws_security_group" "node" {
  name        = "${var.name}-sg"
  description = "SSH from one address; all UIs reached via SSH tunnel"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = "${var.name}-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.node.id
  description       = "SSH from the operator's address only"
  cidr_ipv4         = local.ssh_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

# Egress stays open: the node pulls k3s, Istio, Helm charts, container images
# from GHCR and the ArgoCD manifests. Restricting this to a registry allowlist
# is a Zero-Trust-project concern, not a day-one one.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.node.id
  description       = "Outbound for package, chart and image pulls"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
