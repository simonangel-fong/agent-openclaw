# Openclaw - Local Docker

[Back](../README.md)

- [Openclaw - Local Docker](#openclaw---local-docker)
  - [Architecture](#architecture)
  - [Ollama service](#ollama-service)
  - [OpenWebUI service](#openwebui-service)
  - [OpenClaw service](#openclaw-service)
  - [Clean up](#clean-up)

---

## Architecture

```
                +----------------+
  browser  -->  |   OpenWebUI    |  --\
                +----------------+     \
                                        +-->  +-------------------+
                +----------------+     /      |      Ollama       |
  agent    -->  |   OpenClaw     |  --/       | (qwen2.5-coder)   |
                +----------------+            +-------------------+
```

- **OpenWebUI** → Ollama native integration (chat).
- **OpenClaw** → Ollama **native** API with `api: "ollama"`. Do **not** use the
  `/v1` OpenAI-compatible URL — per the docs it breaks tool calling and the model
  emits raw tool-call JSON as plain text.

---

- Environement:
  - Local: Laptop, <7GB RAM; CPU
  - OS: Windows
  - Container: Docker Deskop

- Model:
  - qwen2.5-coder:1.5b: requires limited resource

---

## Ollama service

- Bring up the local **Ollama** service
  - pulls `qwen2.5-coder:1.5b` (a tool-capable model — see note below)
  - persist to `./data/ollama`;

```sh
docker compose up -d ollama
# [+] Running 1/1
#  ✔ Container ollama  Running

# watch model pull
docker compose logs -f ollama

# confirm
docker compose ps
# NAME      IMAGE                  COMMAND                  SERVICE   CREATED         STATUS                   PORTS
# ollama    ollama/ollama:latest   "/bin/sh -c 'ollama …"   ollama    9 minutes ago   Up 9 minutes (healthy)   0.0.0.0:11434->11434/tcp, [::]:11434->11434/tcp

docker compose exec ollama ollama list
# NAME                  ID              SIZE      MODIFIED
# qwen2.5-coder:1.5b    d7372fd82851    986 MB    7 minutes ago

docker compose exec ollama ollama run qwen2.5-coder:1.5b "In one sentence, who are you?"
# I am an AI language model created by Alibaba Cloud.
```

---

## OpenWebUI service

- Browser chat frontend for talking to the model directly
  - native Ollama integration at `http://ollama:11434`
  - persist to `./data/openwebui`
  - open `http://localhost:3000`, pick `qwen2.5-coder:1.5b`, then ask
    "Who are you?" / "What is an LLM?"

```sh
docker compose up -d openwebui

# confirm: http://localhost:3000/
docker compose ps
# NAME        IMAGE                                COMMAND                  SERVICE     CREATED          STATUS                    PORTS
# ollama      ollama/ollama:latest                 "/bin/sh -c 'ollama …"   ollama      55 minutes ago   Up 55 minutes (healthy)   0.0.0.0:11434->11434/tcp, [::]:11434->11434/tcp
# openwebui   ghcr.io/open-webui/open-webui:main   "bash start.sh"          openwebui   34 minutes ago   Up 34 minutes (healthy)   0.0.0.0:3000->8080/tcp, [::]:3000->8080/tcp

```

---

## OpenClaw service

The agent, wired to the **native** Ollama API (no `/v1`). Two services:

- `openclaw-gateway` — the agent daemon + Control UI on `:18789`.
- `openclaw-cli` — a **one-shot** onboarding run that writes the config, then
  exits (it does not stay up).

The gateway needs a token. Generate one into `.env` (gitignored) first:

```sh
# .env  ->  OPENCLAW_GATEWAY_TOKEN=<64 hex chars>
openssl rand -hex 32
```

Onboard against Ollama, then start the gateway:

```sh
# 1. one-shot onboarding (writes ~/.openclaw/openclaw.json, points at Ollama)
docker compose run --rm openclaw-cli

# 2. start / reload the gateway to pick up the config
docker compose up -d openclaw-gateway

# confirm all three services: http://localhost:18789/
docker compose ps
# NAME               STATUS                    PORTS
# ollama             Up (healthy)              0.0.0.0:11434->11434/tcp
# openwebui          Up (healthy)              0.0.0.0:3000->8080/tcp
# openclaw-gateway   Up (healthy)              0.0.0.0:18789->18789/tcp
```

Verify the agent end-to-end (text task — see the DoD scope note in the plan):

```sh
docker compose exec openclaw-gateway \
  openclaw agent --session-id haiku \
  --message "Write a haiku about the ocean. Reply with only the haiku."
# Whispers dance in the sea,
# Silent waves whisper secrets deep,
# Ocean whispers to all.
```

---

## Clean up

Tear down (`-v` also removes named volumes and the `./data` bind content):

```sh
docker compose down -v
```
