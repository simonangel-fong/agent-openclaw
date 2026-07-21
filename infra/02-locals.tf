locals {

  project    = "openclaw"
  env        = "dev"
  aws_region = "us-east-1"

  ec2_instance_type  = "g4dn.xlarge"
  ec2_root_volume_gb = 75 # DL AMI needs >75GB snapshot

  openclaw_repo_url = "https://github.com/simonangel-fong/agent-openclaw.git"
  openclaw_model_id = "qwen2.5-coder:1.5b"

}
