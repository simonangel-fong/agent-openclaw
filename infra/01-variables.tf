
variable "my_ip" {
  description = "Your public IP in CIDR form (e.g. 203.0.113.4/32). All inbound is locked to this."
  type        = string
}

variable "ssh_key_name" {
  description = "Name of an existing EC2 key pair in this region for SSH access."
  type        = string
}
