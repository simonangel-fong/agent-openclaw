# 03 — Migrate the stack to Kubernetes (local, Docker Desktop, CPU)

Run the working Docker Compose stack on the **Kubernetes cluster built into
Docker Desktop** (context `docker-desktop`), CPU-only. No cloud, no ingress —
access is via `kubectl port-forward`.

> Scope mirrors the compose stack: text-only DoD, `qwen2.5-coder:1.5b`, no GPU,
> no tool-calling tasks. This proves the stack runs on k8s; it does not change app
> behavior.

## Cluster: Docker Desktop (not kind)

The cluster is already up — `kubectl config current-context` → `docker-desktop`,
and `kube-system` pods are Running. **No `kind` install needed.** (Docker
Desktop's k8s happens to use kindnet under the hood, but you manage it through
Docker Desktop, not the `kind` CLI.)

```sh
kubectl config current-context      # -> docker-desktop
kubectl get nodes                   # -> desktop-control-plane   Ready
```

## Use existing Helm charts (the easy path)

There **are** maintained charts — we don't have to hand-write everything:

| Component                   | Chart                                | Notes                                                                                                                                                                          |
| --------------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **OpenWebUI + Ollama**      | `open-webui/open-webui` (official)   | Bundles Ollama as a **subchart** (`ollama.enabled: true`) and can **pull the model on startup** (`ollama.models.pull`). One `helm install` covers **both** services.           |
| **Ollama** (standalone alt) | `otwld/ollama-helm`                  | The subchart the above pulls in; use directly only if you want Ollama separate.                                                                                                |
| **OpenClaw**                | community charts + official k8s docs | No single vendor chart, but `docs.openclaw.ai/install/kubernetes` documents the exact pattern; community charts exist (e.g. `serhanekicii/openclaw-helm`, `iMerica/kubeclaw`). |

**Chosen split — both via Helm:**

- **OpenWebUI + Ollama → the official Helm chart** (collapses two services into
  one install, handles PVC + model pull).
- **OpenClaw → the community chart** `serhanekicii/openclaw-helm`, **including a
  Slack messaging channel**. This chart is built on `bjw-s app-template`, so:
  - Config is supplied **declaratively via a ConfigMap** (`openclaw.json`) — **no
    initContainer onboard step**. We hand it the Ollama provider + Slack channel
    directly.
  - Secrets (Slack tokens, gateway token) come from a Kubernetes Secret via
    `envFrom`, referenced in `openclaw.json` as `${ENV_VAR}`.

> This differs from the compose flow: compose used a one-shot `openclaw onboard`
> to _write_ config; the chart instead _declares_ config up front. Same end
> state (a gateway pointed at Ollama), fewer moving parts on k8s.

## Migration steps (Ollama → UI → OpenClaw)

### Phase 0 — cluster + namespace

1. Confirm context is `docker-desktop` and the node is `Ready` (above).
2. `kubectl create namespace openclaw`.
3. `helm repo add open-webui https://helm.openwebui.com/ && helm repo update`.

### Phase 1 + 2 — Ollama **and** OpenWebUI (one Helm install)

The official chart brings up Ollama (subchart) and points OpenWebUI at it
automatically. Values live in
[`k8s/openwebui-values.yaml`](../k8s/openwebui-values.yaml):

```yaml
ollama:
  enabled: true # install Ollama as a subchart
  ollama: # inner block → forwarded to otwld/ollama-helm
    models:
      pull:
        - qwen2.5-coder:1.5b # pull our model on startup
    persistentVolume:
      enabled: true # keep the MODEL across restarts (avoids re-pull)
persistence:
  enabled: false # OpenWebUI chats NOT persisted (per decision)
extraEnvVars:
  - name: WEBUI_AUTH # disable login (matches compose)
    value: "false"
  - name: DEFAULT_USER_ROLE # any signup becomes admin, not "pending"
    value: "admin"
  - name: ENABLE_SIGNUP
    value: "true"
service:
  type: ClusterIP # no ingress; we port-forward
pipelines:
  enabled: false # not needed for the text DoD
```

> **Gotcha — `WEBUI_AUTH=false` only applies to a FRESH database.** If you sign
> up once, OpenWebUI creates an admin and then _ignores_ the flag, leaving new
> sessions on an "Account Activation Pending" screen. Because persistence is off,
> the SQLite DB is ephemeral — just **roll the pod** to get a clean no-auth boot:
> `kubectl -n openclaw rollout restart deploy/openwebui-open-webui`.
> The `DEFAULT_USER_ROLE=admin` above is the belt-and-suspenders fallback.

> **Key nesting bug to avoid:** the model-pull keys are under the **second**
> `ollama:` (`ollama.ollama.models.pull`), not `ollama.models.pull` — the inner
> block passes straight through to the `otwld/ollama-helm` subchart.

```sh
helm install openwebui open-webui/open-webui \
  -n openclaw -f k8s/openwebui-values.yaml
```

**Verify:**

- `kubectl -n openclaw get pods` → `openwebui-ollama`, `openwebui-open-webui`
  Running (model pull ~986 MB may take a few min; watch
  `kubectl -n openclaw logs -f deploy/openwebui-ollama`).
- `kubectl -n openclaw exec deploy/openwebui-ollama -- ollama list` shows
  `qwen2.5-coder:1.5b`.
- `kubectl -n openclaw port-forward svc/openwebui-open-webui 8080:80` → open
  `http://localhost:8080`, ask "Who are you?" / "What is an LLM?".

> The chart names the Ollama Service **`openwebui-ollama`** (:11434) — verified
> from the rendered manifest. OpenClaw must point at **that** name, not `ollama`.
> Confirm with `kubectl -n openclaw get svc`.

### Phase 3 — OpenClaw (community Helm chart + Slack)

First find the Ollama Service the OpenWebUI chart created — OpenClaw points at it:

```sh
kubectl -n openclaw get svc | grep ollama    # e.g. openwebui-ollama  ClusterIP  ...:11434
```

1. **Add the chart repo:**
   ```sh
   helm repo add openclaw https://serhanekicii.github.io/openclaw-helm
   helm repo update
   ```
2. **Secret** with the gateway token **and Slack tokens** (Slack Socket Mode needs
   both a bot token and an app token — no public URL required, ideal for local):
   ```sh
   kubectl -n openclaw create secret generic openclaw-env-secret \
     --from-literal=OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32) \
     --from-literal=SLACK_BOT_TOKEN=xoxb-... \
     --from-literal=SLACK_APP_TOKEN=xapp-...
   ```
3. **Values** live in [`k8s/openclaw-values.yaml`](../k8s/openclaw-values.yaml)
   (validated with `helm template` against the cluster's k8s version). Everything
   nests under `app-template:` (the chart's `bjw-s` base). Key points:
   - `configMaps.config.data.openclaw.json` holds the config. The chart's
     **`init-config` container merges** it into the PVC on startup (respecting
     `configMode: merge`) — so **no `openclaw onboard` step**.
   - We **override the chart default** (`anthropic/claude-opus-4-6`) with the
     Ollama provider + `ollama/qwen2.5-coder:1.5b`, and point `baseUrl` at
     **`openwebui-ollama:11434`**.
   - We **trim chart extras**: `skills: []` (no ClawHub install), web
     search/fetch off. `browser.enabled: false` disables the *feature* but the
     chart still runs a Chromium **sidecar** container (harmless, idles).
   - **No `gateway.auth` token.** Local + port-forward only, so token auth is
     omitted (matches the chart default). An earlier `gateway.auth.token` block
     with `{source,id}` was **rejected** by this OpenClaw version
     (`gateway.auth.token: Invalid input`) — leaving it off is simplest.
   - `envFrom` loads `openclaw-env-secret` (Slack tokens); `openclaw.json`
     references them as `${SLACK_BOT_TOKEN}` etc.

   > **`configMode: merge` trap:** merge never *removes* keys already on the PVC.
   > If you edit the config and re-upgrade, a bad key persists — uninstall +
   > delete the `openclaw` PVC, then reinstall for a clean write.

   > ✅ **Verified:** after a clean install the gateway logs `agent model:
   > ollama/qwen2.5-coder:1.5b` and `ready`; the web UI (port-forward `:18789`)
   > returns a coherent reply; and the CLI below returns a haiku from the local
   > model. Note the CLI needs a session target — pass `--session-id main`
   > (without it: `No target session selected`).

4. **Install:**
   ```sh
   helm install openclaw openclaw/openclaw -n openclaw -f k8s/openclaw-values.yaml
   ```

**Verify:**

- `kubectl -n openclaw port-forward svc/openclaw 18789:18789`.
- Text DoD task through the pod (`main` container):
  `kubectl -n openclaw exec deploy/openclaw -c main -- \
openclaw agent --message "Write a haiku about the ocean."`
- **Slack path:** message the bot in Slack; confirm it replies via the local
  model. (Approve device pairing if prompted — see the chart's onboarding notes.)

### Phase 4 — parity check / teardown

- Re-run the **exact text DoD** from [the plan](00-plan.md). Same results as
  compose = migration verified.
- Teardown:
  `helm -n openclaw uninstall openclaw openwebui && kubectl delete ns openclaw`.

## Key differences from compose (things to get right)

- **Ollama Service name changes.** The OpenWebUI chart names it (e.g.
  `openwebui-ollama`), **not** `ollama`. OpenClaw's `baseUrl` must use the real
  Service name — check `kubectl get svc` first.
- **Declarative config, no onboard CLI.** The chart _declares_ `openclaw.json`
  via ConfigMap; there is **no `openclaw onboard` step**. Same end state.
- **`depends_on` → readiness probes.** The OpenWebUI chart orders Ollama↔UI; the
  OpenClaw pod just needs Ollama's Service to resolve (it will retry).
- **`.env` token → Secret**; Slack tokens live in the same Secret, referenced as
  `${SLACK_BOT_TOKEN}` / `${SLACK_APP_TOKEN}` in `openclaw.json`.
- **Bind mounts → PVCs** (Docker Desktop's default StorageClass provisions them).
- **No ingress.** `kubectl port-forward` per service, as requested. Slack uses
  **Socket Mode**, so it needs no inbound/public URL.

## Proposed file layout

```
k8s/
  openwebui-values.yaml   # Helm values: Ollama subchart + model pull + WEBUI_AUTH
  openclaw-values.yaml    # Helm values: openclaw.json ConfigMap (Ollama + Slack) + Secret ref
```

## Prerequisites you must supply

- **A Slack app with Socket Mode enabled**, giving a **bot token** (`xoxb-…`) and
  an **app-level token** (`xapp-…`). These go into `openclaw-env-secret`.
- Everything else (cluster, model, tokens) is generated in the steps above.

---

## Development

### Phase 0 — namespace + repo

```sh
kubectl create namespace openclaw
helm repo add open-webui https://helm.openwebui.com/ && helm repo update
```

### Phase 1 + 2 — Ollama + OpenWebUI (one Helm install)

Values live in [`k8s/openwebui-values.yaml`](../k8s/openwebui-values.yaml).
Validated with `helm template` (renders cleanly; model-pull, `WEBUI_AUTH`, and
`ClusterIP` confirmed applied).

```sh
# install the chart (Ollama subchart + model pull on startup)
helm install openwebui open-webui/open-webui -n openclaw -f k8s/openwebui-values.yaml

# confirm
kubectl -n openclaw get pods
# NAME                                          READY   STATUS    RESTARTS   AGE
# openwebui-ollama-6779f784-bmcqx               1/1     Running   0          13m
# openwebui-open-webui-7b58dbc44f-cgtx9         1/1     Running   0          13m
# openwebui-open-webui-redis-6bd8798b4d-dtx2j   1/1     Running   0          13m

kubectl -n openclaw exec deploy/openwebui-ollama -- ollama list
# NAME                  ID              SIZE      MODIFIED
# qwen2.5-coder:1.5b    d7372fd82851    986 MB    4 minutes ago

kubectl -n openclaw get svc
# NAME                         TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)     AGE
# openwebui-ollama             ClusterIP   10.96.70.241   <none>        11434/TCP   14m
# openwebui-open-webui         ClusterIP   10.96.70.131   <none>        80/TCP      14m
# openwebui-open-webui-redis   ClusterIP   10.96.145.18   <none>        6379/TCP    14m

kubectl -n openclaw port-forward svc/openwebui-open-webui 8080:80
# open http://localhost:3000  ->  ask "Who are you?" / "What is an LLM?"
```

Tear down just this release (keeps the namespace):

```sh
helm -n openclaw uninstall openwebui
```

### Phase 3 — OpenClaw (community chart + Slack)

Values in [`k8s/openclaw-values.yaml`](../k8s/openclaw-values.yaml). Requires a
Slack app with **Socket Mode** enabled (gives `xoxb-…` bot + `xapp-…` app tokens).

```sh
# add the community chart repo
helm repo add openclaw https://serhanekicii.github.io/openclaw-helm && helm repo update

# secret: gateway token + Slack tokens
kubectl -n openclaw create secret generic openclaw-env-secret \
  --from-literal=OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32) \
  --from-literal=SLACK_BOT_TOKEN=<xoxb-bot-token> \
  --from-literal=SLACK_APP_TOKEN=<xapp-app-token>

# secret/openclaw-env-secret created

# install
helm install openclaw openclaw/openclaw -n openclaw -f k8s/openclaw-values.yaml

# watch it come up
kubectl -n openclaw get pods -w
# openclaw-...   Running   (has an init-config initContainer that runs first)

# Verify 
kubectl -n openclaw exec deploy/openclaw -c main -- \
  openclaw agent --session-id main --message "Write a haiku about the ocean."

# Wave cradles sand,
# Breeze whispers secrets,
# Sea calms dreams.

# UI: http://localhost:18789 and chat
kubectl -n openclaw port-forward svc/openclaw 18789:18789
# (or, with Slack tokens set, message the bot — it replies via the local model)
```

Full teardown:

```sh
helm -n openclaw uninstall openclaw openwebui && kubectl delete ns openclaw
```
