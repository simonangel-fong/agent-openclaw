# Plan: Run a local LLM + OpenClaw fully locally

## Goal

Run a fully local, offline AI stack — no cloud APIs, no per-token cost:

- **Ollama** serves a local model (**`qwen2.5-coder`**) on CPU.
- **OpenWebUI** is the browser chat frontend for talking to the model directly.
- **OpenClaw** is the agent, pointed at the local Ollama model (not OpenAI).

> **Model note.** Originally planned around `gemma3`, but gemma3 reports
> `capabilities: [completion]` only — no `tools` — and OpenWebUI attaches tools
> to chat by default, so every message errored with `does not support tools`.
> Switched to **`qwen2.5-coder`** (`completion, tools, insert`), which clears
> that error. See the DoD scope note on why tooling is still out of scope on this
> hardware.

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

All run as Docker Compose services on one network, reaching Ollama at
`http://ollama:11434`. Endpoint choice differs by consumer:

- **OpenWebUI** → Ollama native integration (chat).
- **OpenClaw** → Ollama **native** API with `api: "ollama"`. Do **not** use the
  `/v1` OpenAI-compatible URL — per the docs it breaks tool calling and the model
  emits raw tool-call JSON as plain text.

## Scope (in / out)

- **In:** local Ollama + `qwen2.5-coder`, OpenWebUI frontend, OpenClaw wired to
  Ollama, verified end-to-end with the **text** task below.
- **Out:** cloud providers (OpenAI API), multi-user auth, TLS/remote access, GPU
  tuning, and **agent tool/code-execution tasks** (see DoD scope note).

## Steps

1. **Ollama service** — add to `docker-compose.yaml`; mount `./data/ollama` for
   model storage; pull `qwen2.5-coder:1.5b` on first run (`:7b` answers better
   but is slow on CPU). `1.5b` is the working default.
2. **OpenWebUI service** — add to compose; point it at the Ollama service
   (`http://ollama:11434`) via its native Ollama integration.
3. **OpenClaw service** — onboard against Ollama (not OpenAI). Two services:
   `openclaw-gateway` (daemon + Control UI on `:18789`) and a one-shot
   `openclaw-cli` that runs `openclaw onboard`. Use the native Ollama provider
   (NOT `/v1`):

   ```json5
   {
     models:  { providers: { ollama: { baseUrl: "http://ollama:11434", api: "ollama" } } },
     agents:  { defaults:  { model: { primary: "ollama/qwen2.5-coder:1.5b" } } }
   }
   ```

   Onboard flags: `--auth-choice=ollama`, `--custom-base-url`,
   `--custom-model-id`, token gateway auth via `OPENCLAW_GATEWAY_TOKEN`, and
   `--gateway-bind=lan` (so the mapped host port reaches the gateway). No
   `OPENAI_API_KEY` anywhere.
4. **Bring it up** — start the services; run the one-shot onboarding; confirm all
   three containers healthy. See `docs/01-docker.md` for exact commands.

## Definition of Done

> **Scope note — text-only, no tooling.** Target hardware is **CPU-only with
> <7 GB RAM**. A model that reliably emits *structured* tool calls on Ollama
> needs more than that; the small models that fit (`qwen2.5-coder:1.5b/7b`)
> return tool-call JSON as plain text, which OpenClaw correctly won't execute.
> So the DoD is scoped to **text generation only** — no tool/code-execution
> tasks. Tool calling is deferred until better hardware (or a GPU) is available.

- [x] All three containers (ollama, openwebui, openclaw) start and stay up.
- [x] `qwen2.5-coder` is pulled and listed by `ollama list` inside the container.
- [x] **OpenWebUI ↔ Ollama** — verified via the `openwebui → ollama:11434` path:
  - [x] "Who are you?" returns a coherent response.
  - [x] "What is an LLM?" returns a coherent response.
- [x] **OpenClaw ↔ Ollama** — verified via the agent, no OpenAI key in use:
  - [x] A plain text prompt (e.g. "Write a haiku about the ocean.") returns a
        coherent reply — confirms the agent → Ollama text path works.
- [x] No cloud API calls made — verified offline: containers moved to an
      `--internal` network (internet `fetch` fails), agent task still returned a
      full response from local Ollama.
