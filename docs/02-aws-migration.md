# 02 — Migrate the stack to an AWS EC2 GPU instance

## Will a GPU actually help?

**Yes — substantially.** The local box is CPU-only with <7 GB RAM, which is why
the DoD was scoped to text-only (see [the plan](00-plan.md)). A GPU changes two
things:

|                      | Local (CPU, <7 GB)                                        | EC2 `g4dn.xlarge` (T4, 16 GB VRAM)                                                                               |
| -------------------- | --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `qwen2.5-coder:1.5b` | works, slow-ish                                           | fast (sub-second first token)                                                                                    |
| `qwen2.5-coder:7b`   | ~9 s/turn when warm                                       | comfortable, interactive                                                                                         |
| Bigger models (14b)  | won't fit / unusable                                      | fits quantized, runs well                                                                                        |
| **Tool calling**     | ❌ blocked (small models emit text, not structured calls) | ✅ a 7b/14b that fits GPU can emit structured tool calls — **re-enables the weather + hello-world Python tasks** |

So the GPU doesn't just speed things up; it lets you run a model large enough to
cross the tool-calling threshold you had to descope locally.

## Target architecture

Same three services, same [`docker-compose.yaml`](../docker-compose.yaml) — the
**app layer does not change**. We add:

- A **GPU-enabled EC2 instance** (`g4dn.xlarge`, 1× NVIDIA T4, 16 GB VRAM).
- **NVIDIA driver + NVIDIA Container Toolkit** on the host (so Docker can see the
  GPU).
- A small compose change so the `ollama` service **requests the GPU**.
- **Terraform** to manage the EC2 instance, security group, and bootstrap.

```
                         EC2 g4dn.xlarge (Ubuntu 22.04, NVIDIA driver + toolkit)
  you (browser) --443/HTTP--> [ SG: your-IP only ]
                                 :3000  OpenWebUI ─┐
                                 :18789 OpenClaw  ─┼─► :11434 Ollama ──► T4 GPU
                                 :11434 Ollama ────┘
```

## Decisions (locked)

| Decision  | Choice                                                            | Why                                            |
| --------- | ----------------------------------------------------------------- | ---------------------------------------------- |
| Instance  | `g4dn.xlarge` (~$0.526/hr)                                        | Cheapest GPU that clears the tooling wall      |
| Exposure  | Security group locked to **your IP**, plain HTTP                  | Simple + safe for a personal box               |
| Bootstrap | Terraform `user_data` → install Docker+GPU, clone, `compose up`   | Fully automated, repeatable                    |
| Model     | **Start with `1.5b`** (prove parity), then upgrade to `7b`/larger | De-risk migration first, unlock tooling second |

## GPU changes to `docker-compose.yaml`

Only the `ollama` service needs to request the GPU. Add to its definition:

```yaml
ollama:
  # ...existing config...
  deploy:
    resources:
      reservations:
        devices:
          - driver: nvidia
            count: 1
            capabilities: [gpu]
```

> Keep the CPU-only compose working locally by putting the GPU block in a compose
> **override** (`docker-compose.gpu.yaml`) applied only on EC2:
> `docker compose -f docker-compose.yaml -f docker-compose.gpu.yaml up -d`.
> That way the same base manifest runs in both places (requirement #2).

Everything else — OpenWebUI, OpenClaw gateway + one-shot onboarding, the
`OPENCLAW_GATEWAY_TOKEN` flow — is **unchanged**. Onboarding still points at
`http://ollama:11434` with `api: "ollama"`.

## Terraform scope (keep it minimal)

One small root module, ~4 resources:

```
infra/
  main.tf         # provider, EC2 instance, security group, EIP (optional)
  variables.tf    # region, instance_type, my_ip, ssh_key_name, model_id
  outputs.tf      # public_ip, urls
  user_data.sh    # host bootstrap (below)
```

- **`aws_instance`** — `g4dn.xlarge`, Ubuntu 22.04 (or the AWS Deep Learning Base
  GPU AMI, which ships NVIDIA drivers — simplest), a root EBS volume ~100 GB
  (models are large), the `user_data` script.
- **`aws_security_group`** — inbound `3000`, `18789`, `11434`, and `22` (SSH),
  each restricted to `var.my_ip/32`. Outbound all (needed for image + model
  pulls on first boot).
- **`aws_eip`** _(optional)_ — a stable public IP so it survives stop/start.
- Variables you set: `my_ip`, `ssh_key_name`, `region`.

### `user_data.sh` (host bootstrap)

```sh
#!/bin/bash
set -euxo pipefail
# 1. Docker
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu
# 2. NVIDIA Container Toolkit (driver assumed present via DL GPU AMI)
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  > /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update && apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker && systemctl restart docker
# 3. App
cd /opt && git clone <YOUR_REPO_URL> agent-openclaw && cd agent-openclaw
echo "OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)" > .env
docker compose -f docker-compose.yaml -f docker-compose.gpu.yaml up -d ollama openwebui openclaw-gateway
docker compose run --rm openclaw-cli   # one-shot onboarding
docker compose -f docker-compose.yaml -f docker-compose.gpu.yaml up -d openclaw-gateway
```

## Migration steps (local first, then EC2)

### Phase A — prove it locally (no AWS spend)

1. Add `docker-compose.gpu.yaml` (the GPU override above).
2. Confirm the **base** compose still works CPU-only:
   `docker compose up -d` → run the text DoD task. (Already ✅ today.)
3. Push the repo to a git remote the instance can clone.

### Phase B — stand up EC2 with Terraform

4. `cd infra && terraform init && terraform apply` (pass `my_ip`, `ssh_key_name`).
5. Wait for `user_data` to finish (~5–10 min: driver + toolkit + image pulls +
   model pull). Watch via `ssh ... 'tail -f /var/log/cloud-init-output.log'`.
6. Verify the GPU is visible to Docker:
   `docker compose exec ollama nvidia-smi` (should list the T4).

### Phase C — verify parity on EC2 (still `1.5b`)

7. Repeat the **exact DoD** from the plan against the public IP:
   - OpenWebUI: `http://<public-ip>:3000` → "Who are you?" / "What is an LLM?"
   - OpenClaw: `openclaw agent --message "Write a haiku..."`
8. This proves the migration is correct before changing anything else.

### Phase D — upgrade the model, unlock tooling

9. `docker compose exec ollama ollama pull qwen2.5-coder:7b` (or 14b).
10. Point OpenClaw at it:
    `openclaw config set agents.defaults.model.primary "ollama/qwen2.5-coder:7b"`
    then restart the gateway.
11. Re-test the **tool** tasks that were descoped locally: "weather in NY",
    "run a hello world Python program". Confirm structured tool calls now fire.
12. If tooling still misbehaves, bump the model — **do not switch to `/v1`**
    (same rule as the local plan).

## Budget

On-demand `g4dn.xlarge` in `us-east-1` ≈ **$0.526/hr** (~$384/mo if left on 24/7).

| Usage pattern                                        | Est. cost                |
| ---------------------------------------------------- | ------------------------ |
| 1-hour smoke test (apply → verify → destroy)         | ~**$0.53** + pennies EBS |
| Dev sessions, ~3 hr/day, 20 days/mo                  | ~**$32/mo** compute      |
| Left running 24/7                                    | ~**$384/mo** compute     |
| EBS root (100 GB gp3, always billed while it exists) | ~**$8/mo**               |
| Data transfer out (light UI use)                     | a few $/mo               |

**Cost-control levers (keep it cheap):**

- **Stop the instance** when idle — you pay only EBS (~$8/mo) while stopped.
  `terraform apply` again / `aws ec2 start-instances` to resume. An EIP keeps the
  IP stable across stop/start.
- **`terraform destroy`** between experiments to drop to ~$0 (you re-pull models
  on next boot — the `user_data` handles it).
- Consider **Spot** for ~60–70% off if interruption is acceptable (a later
  optimization, not for the first migration).

## What's still out of scope

- Multi-user auth, TLS/HTTPS (using IP-restricted HTTP), autoscaling, managed
  model storage (S3), and CI/CD for the instance. All deferrable.
