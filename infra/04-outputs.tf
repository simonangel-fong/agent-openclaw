output "public_ip" {
  description = "Stable public IP (EIP) of the instance."
  value       = aws_eip.openclaw.public_ip
}

output "urls" {
  description = "Service endpoints (IP-restricted to my_ip)."
  value = {
    openwebui = "http://${aws_eip.openclaw.public_ip}:3000"
    openclaw  = "http://${aws_eip.openclaw.public_ip}:18789"
    ollama    = "http://${aws_eip.openclaw.public_ip}:11434"
  }
}

output "ssh" {
  description = "SSH command (DL GPU AMI default user is ubuntu)."
  value       = "ssh -i '${var.ssh_key_name}.pem' ubuntu@${aws_eip.openclaw.public_ip}"
}

output "watch_bootstrap" {
  description = "Tail cloud-init to watch user_data progress."
  value       = "ssh ubuntu@${aws_eip.openclaw.public_ip} 'tail -f /var/log/cloud-init-output.log'"
}
