locals {

  project    = "openclaw"
  env        = "dev"
  aws_region = "us-east-1"

  ec2_instance_type  = "g4dn.xlarge"
  ec2_root_volume_gb = 50

  openclaw_repo_url = "https://github.com/simonangel-fong/agent-openclaw.git"
  openclaw_model_id = "qwen2.5-coder:1.5b"

}
