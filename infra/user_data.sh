#!/bin/bash
set -euxo pipefail

# 1. Docker
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu

# 2. NVIDIA Container Toolkit (driver already present via DL GPU AMI)
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  > /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update && apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker && systemctl restart docker

# 3. App
cd /opt
git clone ${repo_url} agent-openclaw
cd agent-openclaw
echo "OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)" > .env

COMPOSE="docker compose -f docker-compose.yaml -f docker-compose.gpu.yaml"

# Bring up services (onboarding container writes config, then exits).
$COMPOSE up -d ollama openwebui openclaw-gateway
$COMPOSE run --rm openclaw-cli   # one-shot onboarding
$COMPOSE up -d openclaw-gateway
