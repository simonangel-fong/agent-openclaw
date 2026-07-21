# ec2.tf

data "aws_ami" "dl_gpu" {
  most_recent = true
  owners      = ["898082745236"]

  filter {
    name   = "name"
    values = ["Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04)*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_security_group" "openclaw" {
  name        = "openclaw-sg"
  description = "OpenClaw stack - inbound locked to a single IP."

  # OpenWebUI, OpenClaw Control UI, Ollama, SSH — all locked to my_ip.
  dynamic "ingress" {
    for_each = [3000, 18789, 11434, 22]
    content {
      description = "port ${ingress.value} from my_ip"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = [var.my_ip]
    }
  }

  # Outbound all — needed for image + model pulls on first boot.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "openclaw-sg"
  }
}

resource "aws_instance" "openclaw" {
  ami           = data.aws_ami.dl_gpu.id
  instance_type = local.ec2_instance_type
  key_name      = var.ssh_key_name

  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.openclaw.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size           = local.ec2_root_volume_gb
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = templatefile("${path.module}/user_data.sh", {
    repo_url = local.openclaw_repo_url
    model_id = local.openclaw_model_id
  })

  tags = {
    Name = "openclaw-gpu"
  }
}

resource "aws_eip" "openclaw" {
  instance = aws_instance.openclaw.id
  domain   = "vpc"

  tags = {
    Name = "openclaw-eip"
  }
}
