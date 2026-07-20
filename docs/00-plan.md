# Plan: Run Gemma 3 + OpenClaw fully locally

## Goal

Run a fully local, offline AI stack — no cloud APIs, no per-token cost:

- **Ollama** serves the **Gemma 3** model locally.
- **OpenWebUI** is the browser chat frontend for talking to Gemma directly.
- **OpenClaw** is the agent, pointed at the local Ollama model (not OpenAI).

## Architecture

```
                +----------------+
  browser  -->  |   OpenWebUI    |  --\
                +----------------+     \
                                        +-->  +------------+
                +----------------+     /      |   Ollama   |  (serves gemma3)
  agent    -->  |   OpenClaw     |  --/       +------------+
                +----------------+
```

All three run as Docker Compose services on one network, all reaching Ollama at
`http://ollama:11434`. Endpoint choice differs by consumer:

- **OpenWebUI** → Ollama native integration (chat only, no tools).
- **OpenClaw** → Ollama **native** API with `api: "ollama"`. Do **not** use the
  `/v1` OpenAI-compatible URL for OpenClaw — per the docs it breaks tool calling
  and the model emits raw tool-call JSON as plain text. Tool calling is required
  by the "run hello world Python" DoD task.

## Scope (in / out)

- **In:** local Ollama + Gemma3, OpenWebUI frontend, OpenClaw wired to Ollama,
  verified end-to-end with the tasks below.
- **Out:** cloud providers (OpenAI API), multi-user auth, TLS/remote access,
  GPU tuning beyond "use it if present."

## Steps

1. **Ollama service** — add to `docker-compose.yaml`; mount `./data/ollama` for
   model storage; pull `gemma3:1b` on first run. Upgrade the model (`4b` / `12b`
   / a tool-tuned one like `qwen2.5-coder`) when tasks get complex — a 1B model
   is unreliable at tool calling, so the "run hello world Python" task may need a
   bigger model. If it misbehaves, bump the model — don't switch to `/v1`.
2. **OpenWebUI service** — add to compose; point it at the Ollama service
   (`http://ollama:11434`) via its native Ollama integration.
3. **OpenClaw service** — re-onboard against Ollama instead of OpenAI. Use the
   native Ollama provider (NOT `/v1`):

   ```json5
   {
     models:  { providers: { ollama: { baseUrl: "http://ollama:11434", api: "ollama" } } },
     agents:  { defaults:  { model: { primary: "ollama/gemma3:1b" } } }
   }
   ```

   Drop `--auth-choice openai-api-key` and `OPENAI_API_KEY`; keep the gateway
   token setup.
4. **Bring it up** — `docker compose up -d`; confirm all three containers healthy.

> Note: current `docker-compose.yaml` + `docs/01-docker.md` are still wired for
> `OPENAI_API_KEY`. Reworking those to the local Ollama endpoint is the main
> code change this plan drives.

## Definition of Done

- [ ] All three containers (ollama, openwebui, openclaw) start and stay up.
- [ ] `gemma3` is pulled and listed by `ollama list` inside the container.
- [ ] **OpenWebUI ↔ Ollama** — verified in the browser UI:
  - [ ] "Who are you?" returns a coherent Gemma response.
  - [ ] "What is an LLM?" returns a coherent Gemma response.
- [ ] **OpenClaw ↔ Ollama** — verified via the agent, no OpenAI key in use:
  - [ ] "What is the weather like in NY?" (exercises a tool/response path).
  - [ ] "Create and run a hello world Python program" (exercises code execution).
- [ ] No cloud API calls made — confirmed offline (unplug network, tasks still work).
