output "public_ip" {
  description = "Current public address of the node."
  value       = aws_instance.node.public_ip
}

output "instance_id" {
  description = "Instance id, for the teardown check."
  value       = aws_instance.node.id
}

output "ssh_command" {
  description = "Plain SSH."
  value       = "ssh ubuntu@${aws_instance.node.public_ip}"
}

output "tunnel_command" {
  description = <<-EOT
    SSH with every UI forwarded. This is how the platform is reached — no UI
    port is open in the security group.
      8080 ArgoCD · 3000 Grafana · 9090 Prometheus · 9093 Alertmanager · 20001 Kiali
  EOT
  value = join(" ", [
    "ssh",
    "-L 8080:localhost:8080",
    "-L 3000:localhost:3000",
    "-L 9090:localhost:9090",
    "-L 9093:localhost:9093",
    "-L 20001:localhost:20001",
    "ubuntu@${aws_instance.node.public_ip}",
  ])
}

output "allowed_ssh_cidr" {
  description = "The address :22 was opened to. Confirm this is yours."
  value       = local.ssh_cidr
}

output "hourly_cost_reminder" {
  description = "Read this at the end of every session."
  value       = "${var.instance_type} bills ~$0.166/hour while running. Run 'terraform destroy' when you stop for the day."
}
