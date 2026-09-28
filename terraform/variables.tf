variable "region" {
  description = "AWS region. us-east-1 to match the rest of the account."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = <<-EOT
    16 GB is the requirement, not a preference. The full stack — k3s, Istio,
    ArgoCD, Prometheus, Grafana, Loki, Vault, External Secrets and the apps with
    their sidecars — sits at roughly 7.4 GB. An 8 GB node fits that only until
    Prometheus grows toward its limit, and then evicts things. The failure looks
    like random pod restarts rather than a sizing problem, which wastes an
    evening. 16 GB also means the Zero-Trust follow-on needs no resize.
  EOT
  type        = string
  default     = "t3.xlarge"
}

variable "root_volume_size" {
  description = "GB. Container images, Prometheus TSDB and Loki chunks all land here."
  type        = number
  default     = 40
}

variable "public_key_path" {
  description = <<-EOT
    Path to an EXISTING SSH public key. Terraform uploads the public half only.

    Deliberately not tls_private_key: that resource would write the private key
    into terraform.tfstate in plaintext, and state is the one file in an IaC repo
    you cannot afford to leak. Reusing a key you already hold keeps the private
    half off disk in this project entirely.
  EOT
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "allowed_ssh_cidr" {
  description = <<-EOT
    CIDR permitted to reach :22. Leave null to auto-detect this machine's public
    address as a /32.

    Every UI in this project is reached through an SSH tunnel rather than an open
    port, so this is the only ingress rule the box needs. Setting it to
    0.0.0.0/0 puts an unauthenticated ArgoCD and a root-token Vault on the public
    internet within the hour.
  EOT
  type        = string
  default     = null
}

variable "subnet_cidr" {
  description = <<-EOT
    CIDR for the subnet this stack creates inside the default VPC (172.31.0.0/16).

    A /24 is far more address space than one node needs; it is sized this way
    because the Zero-Trust follow-on lands on the same network and a second
    node should not require re-planning the addressing.
  EOT
  type        = string
  default     = "172.31.200.0/24"
}

variable "availability_zone" {
  description = "AZ for the subnet. Leave null to take the first available in the region."
  type        = string
  default     = null
}

variable "name" {
  description = "Name tag and prefix for the instance, key pair and security group."
  type        = string
  default     = "gitops-platform"
}
