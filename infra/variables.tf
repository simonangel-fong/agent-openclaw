variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ca-central-1"
}

variable "instance_type" {
  description = "GPU instance type. g4dn.xlarge = 1x NVIDIA T4, 16 GB VRAM."
  type        = string
  default     = "g4dn.xlarge"
}

variable "my_ip" {
  description = "Your public IP in CIDR form (e.g. 203.0.113.4/32). All inbound is locked to this."
  type        = string
}

variable "ssh_key_name" {
  description = "Name of an existing EC2 key pair in this region for SSH access."
  type        = string
}

variable "model_id" {
  description = "Ollama model to run first. Phase B/C prove parity on 1.5b before upgrading."
  type        = string
  default     = "qwen2.5-coder:1.5b"
}

variable "repo_url" {
  description = "Git URL the instance clones on boot."
  type        = string
  default     = "https://github.com/simonangel-fong/agent-openclaw.git"
}

variable "root_volume_gb" {
  description = "Root EBS volume size in GB. Models are large."
  type        = number
  default     = 100
}
