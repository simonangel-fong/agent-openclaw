## Ollama service

- Bring up the local **Ollama** service
  - pulls `gemma3:1b`
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
# NAME         ID              SIZE      MODIFIED      
# gemma3:1b    8648f39daa8f    815 MB    8 minutes ago    

```
