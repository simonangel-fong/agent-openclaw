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

Pull other models to try (7b is a stronger tool-caller for later steps):

```sh
docker compose exec ollama ollama pull qwen2.5-coder:7b
```

Tear down (`-v` also removes named volumes):

```sh
docker compose down -v
```
