#!/bin/bash
set -euxo pipefail

# 1. Docker
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu

# 2. NVIDIA Container Toolkit (driver already present via DL GPU AMI)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  > /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update && apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker && systemctl restart docker

# 3. App (idempotent: safe to re-run on reboot / cloud-init re-trigger)
cd /opt
if [ -d agent-openclaw/.git ]; then
  git -C agent-openclaw pull --ff-only
else
  git clone ${repo_url} agent-openclaw
fi
cd agent-openclaw

# Generate the gateway token only once — regenerating would orphan the
# already-onboarded gateway.
if [ ! -f .env ]; then
  echo "OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)" > .env
fi

COMPOSE="docker compose -f docker-compose.yaml -f docker-compose.gpu.yaml"

# Bring up services (onboarding container writes config, then exits).
$COMPOSE up -d ollama openwebui openclaw-gateway
$COMPOSE run --rm openclaw-cli   # one-shot onboarding
$COMPOSE up -d openclaw-gateway
