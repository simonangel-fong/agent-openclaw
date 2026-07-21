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

> **Note — OpenClaw Control UI (browser) skipped; verified via CLI instead.**
> The browser Control UI needs a _secure context_ to build device identity —
> it refuses plain HTTP to a public IP, and its WebSocket also fails with
> `1006` over an SSH tunnel to localhost (a known OpenClaw bug in `2026.6.33`;
> `gateway.controlUi.allowInsecureAuth` only relaxes true-localhost sessions,
> not LAN/remote). Getting the browser UI would require HTTPS, which is
> **out of scope** for this migration. **Decision: skip the browser Control UI
> and verify OpenClaw from the command line:**
>
> ```sh
> docker compose -f docker-compose.yaml -f docker-compose.gpu.yaml \
>   run --rm openclaw-cli agent --agent main --message "Write a haiku about GPUs"
> ```
>
> This exercises the same agent → Ollama → GPU path and returned a valid
> completion (`stopReason=stop`). Note the CLI reaches the gateway over the
> same failing WebSocket and transparently falls back to an **embedded agent**
> in the CLI container — expected, and sufficient for parity here.

### Phase D — upgrade the model, unlock tooling

9. `docker compose exec ollama ollama pull qwen2.5-coder:7b` (or 14b).
10. Point OpenClaw at it:
    `openclaw config set agents.defaults.model.primary "ollama/qwen2.5-coder:7b"`
    then restart the gateway.
11. Re-test the **tool** tasks that were descoped locally: "weather in NY",
    "run a hello world Python program". Confirm structured tool calls now fire.
12. If tooling still misbehaves, bump the model — **do not switch to `/v1`**
    (same rule as the local plan).

> **Status — Phase D: PARTIAL (tool threshold crossed; execution blocked).**
>
> - ✅ **The GPU cleared the tool-calling wall.** On `qwen2.5-coder:7b` (loaded
>   on the T4, ~5 GB VRAM) the agent reliably emits **well-formed structured
>   tool calls** — e.g. `{"name":"write",...}` then `{"name":"sessions_send",
>   "message":"python /tmp/hello.py"}` — which `1.5b` could not do. This is the
>   core claim of this migration, and it holds.
> - ❌ **Tool execution does not fire.** OpenClaw `2026.6.33`'s **embedded
>   agent** parses the model output but logs
>   `Assistant reply looks like a tool call, but no structured tool invocation
>   was emitted; treating it as text` and ends `stopReason=stop` without running
>   the tool. No file is written, no code runs. This is an **OpenClaw runtime
>   limitation**, not a model, profile, or infra issue — bumping to `14b`
>   (step 12) does **not** help, since the model is already emitting correct
>   calls. Sharing the gateway network namespace (so the CLI reaches the gateway
>   instead of its own loopback) removed the `ws 1006` error but the agent still
>   routes through the embedded path.
>
> **Decision: mark Phase D partially met and defer.** The migration goal — a GPU
> box that runs a model large enough to emit structured tool calls — is proven.
> Getting those calls to **execute** is follow-up work: try a different pinned
> OpenClaw image tag, or a non-embedded agent runtime, once the upstream bug is
> resolved. Tracked against OpenClaw issues re: embedded-agent tool execution.

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

---

## Development

```sh
docker compose up -d
```

```sh
terraform -chdir=infra init -input=false -backend-config=backend.hcl

terraform -chdir=infra fmt && terraform -chdir=infra validate

terraform -chdir=infra apply -auto-approve

terraform -chdir=infra destroy -auto-approve


ssh -i "<pem>" ubuntu@100.26.64.29


# confirm bootstrap
sudo tail -n 50 /var/log/cloud-init-output.log


sudo docker compose exec ollama nvidia-smi
# Tue Jul 21 15:48:24 2026
# +-----------------------------------------------------------------------------------------+
# | NVIDIA-SMI 595.71.05              Driver Version: 595.71.05      CUDA Version: 13.2     |
# +-----------------------------------------+------------------------+----------------------+
# | GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
# | Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
# |                                         |                        |               MIG M. |
# |=========================================+========================+======================|
# |   0  Tesla T4                       On  |   00000000:00:1E.0 Off |                    0 |
# | N/A   44C    P0             33W /   70W |    1239MiB /  15360MiB |      0%      Default |
# |                                         |                        |                  N/A |
# +-----------------------------------------+------------------------+----------------------+

# +-----------------------------------------------------------------------------------------+
# | Processes:                                                                              |
# |  GPU   GI   CI              PID   Type   Process name                        GPU Memory |
# |        ID   ID                                                               Usage      |
# |=========================================================================================|
# |    0   N/A  N/A             778      C   /usr/lib/ollama/llama-server           1236MiB |
# +-----------------------------------------------------------------------------------------+

# test
curl -s http://localhost:11434/api/generate -d '{
  "model": "qwen2.5-coder:1.5b",
  "prompt": "Write a haiku about GPUs"
}'
```

---

## Common Commands

| CMD               | Desc                                              |
| ----------------- | ------------------------------------------------- |
| `nvidia-smi`      | the one-shot snapshot (driver, VRAM, temp, procs) |
| `nvidia-smi -L`   | GPU present on host                               |
| `nvidia-smi dmon` | one-line-per-sample: sm%, mem%, power, temp       |
| `nvidia-smi pmon` | per-process monitor                               |

```sh
nvidia-smi
# Tue Jul 21 15:54:03 2026
# +-----------------------------------------------------------------------------------------+
# | NVIDIA-SMI 595.71.05              Driver Version: 595.71.05      CUDA Version: 13.2     |
# +-----------------------------------------+------------------------+----------------------+
# | GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
# | Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
# |                                         |                        |               MIG M. |
# |=========================================+========================+======================|
# |   0  Tesla T4                       On  |   00000000:00:1E.0 Off |                    0 |
# | N/A   44C    P0             33W /   70W |    1239MiB /  15360MiB |      0%      Default |
# |                                         |                        |                  N/A |
# +-----------------------------------------+------------------------+----------------------+

# +-----------------------------------------------------------------------------------------+
# | Processes:                                                                              |
# |  GPU   GI   CI              PID   Type   Process name                        GPU Memory |
# |        ID   ID                                                               Usage      |
# |=========================================================================================|
# |    0   N/A  N/A            8209      C   /usr/lib/ollama/llama-server           1236MiB |
# +-----------------------------------------------------------------------------------------+

nvidia-smi -L
# GPU 0: Tesla T4 (UUID: GPU-98178f31-8a86-f31c-2e94-6c57af3f8ebc)

nvidia-smi --query-gpu=name,memory.total,memory.used,utilization.gpu,temperature.gpu --format=csv
# name, memory.total [MiB], memory.used [MiB], utilization.gpu [%], temperature.gpu
# Tesla T4, 15360 MiB, 105 MiB, 1 %, 44

# get gateway token
grep OPENCLAW_GATEWAY_TOKEN /opt/agent-openclaw/.env | cut -d= -f2

cd /opt/agent-openclaw
sudo docker compose -f docker-compose.yaml -f docker-compose.gpu.yaml \
  run --rm openclaw-cli agents list

# Agents:
# - main (default)
#   Workspace: ~/.openclaw/workspace
#   Agent dir: ~/.openclaw/agents/main/agent
#   Model: ollama/qwen2.5-coder:1.5b
#   Routing rules: 0
#   Routing: default (no explicit rules)
# Routing rules map channel/account/peer to an agent. Use --bindings for full rules.
# Channel status reflects local config/creds. For live health: openclaw channels status --probe.

sudo docker compose -f docker-compose.yaml -f docker-compose.gpu.yaml \
  run --rm openclaw-cli agent --agent main --message "Write a haiku about GPUs"

# Run `openclaw doctor` for diagnostics.
# 16:33:27 [agents/tool-policy] tool policy removed 5 tool(s) via tools.profile (coding): agents_list, gateway, message, nodes, tts
# Gpus like birds soar,
# In graphics land, they dance,
# Nestled in computers.
# [agent] run bbbcd5b5-aac0-4423-8c18-c914ad242e3e ended with stopReason=stop
```

---

```sh
# pull 7b model
cd /opt/agent-openclaw
sudo docker compose -f docker-compose.yaml -f docker-compose.gpu.yaml exec ollama ollama pull qwen2.5-coder:7b

# confirm
sudo docker compose -f docker-compose.yaml -f docker-compose.gpu.yaml exec ollama ollama list
# NAME                  ID              SIZE      MODIFIED
# qwen2.5-coder:7b      dae161e27b0e    4.7 GB    10 seconds ago
# qwen2.5-coder:1.5b    d7372fd82851    986 MB    About an hour ago

# point OpenClaw at 7b
cd /opt/agent-openclaw
CFG=data/openclaw/openclaw.json
sudo cp $CFG $CFG.bak
sudo jq '.agents.defaults.model.primary = "ollama/qwen2.5-coder:7b"' $CFG > /tmp/oc.json \
  && sudo mv /tmp/oc.json $CFG \
  && sudo chown 1000:1000 $CFG \
  && echo "MODEL SET OK"

# MODEL SET OK

# verify
sudo grep -A2 '"model"' $CFG
      # "model": {
      #   "primary": "ollama/qwen2.5-coder:7b"
      # }

# test openclaw with 7b
cd /opt/agent-openclaw
sudo docker compose -f docker-compose.yaml -f docker-compose.gpu.yaml \
  run --rm openclaw-cli agent --agent main \
  --message "Write and run a hello world Python program"


```
