# 04 — Install OpenClaw in WSL (Ubuntu), backed by Claude — ✅ DONE

## Goal

Run OpenClaw natively (npm, no Docker) in **WSL 2 / Ubuntu**, backed by
**Claude**, verified via CLI, then reachable from **Slack**. All phases below are
complete and working.

> **Auth — connected via Claude subscription.** `claude auth login` +
> `openclaw models auth login --method cli` reuses the Claude CLI's OAuth, drawing
> on the Claude plan's usage limits (no separate API bill).
> Alternative: an `ANTHROPIC_API_KEY` from <https://console.anthropic.com>
> (pay-per-token) via `openclaw onboard --anthropic-api-key`.

## Phases (all ✅)

- **A — Fresh WSL Ubuntu:** install WSL 2 + a clean Ubuntu distro.
- **B — Base packages:** git, curl, build tools, python3.
- **C — Node LTS:** install via nvm (apt's Node is too old).
- **D — Install OpenClaw:** global npm install, sanity-check.
- **E — Gateway:** `openclaw doctor` — token, mode, install the systemd service.
- **F — Connect Claude:** `claude auth login` → reuse CLI auth → pick model.
- **G — Verify:** open question + tool tasks (weather, run hello-world Python).
- **H — Connect Slack:** create app, wire tokens, approve sender, test.
- **I — Browser Control UI:** open the gateway dashboard at `127.0.0.1:18789`.

## Gotchas that bit us (read before redoing)

1. **systemd doesn't see your shell env.** The gateway runs as a *systemd user
   service*, so `export SLACK_*` in your shell is invisible to it. Secrets must
   go in `~/.config/openclaw/.env` **and** the service must load it via a drop-in
   (`EnvironmentFile=`) — see Phase H.
2. **Crash-loop breaker.** Repeated failed restarts (e.g. from a missing token)
   trip a breaker that *suppresses channel autostart* even after you fix the
   cause. Clear it with one clean foreground run: `openclaw gateway run --force`.
3. **`groupPolicy: allowlist` drops channel messages.** By default the Slack
   channel only answers in allowlisted channels — the mention arrives but no
   reply goes out. Set `groupPolicy: open` or allowlist the channel **by ID**.
4. **🔑 Rotate the Slack + Claude tokens** used during setup if they were ever
   echoed to a terminal/log — regenerate `xapp-`/`xoxb-` and re-run
   `claude setup-token` if needed.

---

## Commands (as run)

```bash
# --- Phase A (Windows PowerShell) ---
wsl --status                 # check WSL is installed / which version
# Default Distribution: Ubuntu-24.04
# Default Version: 2

wsl.exe --list --online
# The following is a list of valid distributions that can be installed.
# Install using 'wsl.exe --install <Distro>'.

# NAME                            FRIENDLY NAME
# Ubuntu                          Ubuntu
# Debian                          Debian GNU/Linux
# kali-linux                      Kali Linux Rolling
# OracleLinux_7_9                 Oracle Linux 7.9
# OracleLinux_8_10                Oracle Linux 8.10
# OracleLinux_9_5                 Oracle Linux 9.5
# SUSE-Linux-Enterprise-15-SP6    SUSE Linux Enterprise 15 SP6
# openSUSE-Tumbleweed             openSUSE Tumbleweed

wsl.exe --install Ubuntu

wsl.exe --list --verbose
#   NAME              STATE           VERSION
# * Ubuntu-24.04      Stopped         2
#   docker-desktop    Stopped         2
#   Ubuntu            Stopped         2

wsl.exe -d Ubuntu

# --- Phase B (inside Ubuntu) ---
sudo apt-get update && sudo apt-get -y upgrade
sudo apt-get install -y git curl build-essential python3 python3-pip
git --version
# git version 2.43.0

python3 --version
# Python 3.12.3

pip3 --version
# pip 24.0 from /usr/lib/python3/dist-packages/pip (python 3.12)

# --- Phase C (inside Ubuntu) ---
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.6/install.sh | bash
source ~/.bashrc            # load nvm into the current shell
nvm install --lts          # install latest LTS Node
# Installing latest LTS version.
# Downloading and installing node v24.18.0...
# Downloading https://nodejs.org/dist/v24.18.0/node-v24.18.0-linux-x64.tar.xz...

nvm use --lts
# Now using node v24.18.0 (npm v11.16.0)

node --version
# v24.18.0

npm --version
# 11.16.0


# --- Phase D (inside Ubuntu) ---
npm install -g openclaw@latest

openclaw --version
# OpenClaw 2026.7.1-2 (0790d9f)

openclaw doctor                   # environment sanity check


# --- Phase E: Gateway (inside Ubuntu) ---
# required; gateway won't start otherwise
openclaw config set gateway.mode local
# │
# ◇

# 🦞 OpenClaw 2026.7.1-2 (0790d9f)
#    The only crab in your contacts you actually want to hear from. 🦞

# Updated gateway.mode. Restart the gateway to apply.

openclaw doctor
systemctl --user status openclaw-gateway # confirm it's active (running)
# ● openclaw-gateway.service - OpenClaw Gateway (v2026.7.1-2)
#      Loaded: loaded (/home/simonfong/.config/systemd/user/openclaw-gateway.service; enabled; pres>
#      Active: active (running) since Tue 2026-07-21 13:52:37 EDT; 30s ago
#    Main PID: 15378 (MainThread)
#      CGroup: /user.slice/user-1000.slice/user@1000.service/app.slice/openclaw-gateway.service
#              └─15378 /home/simonfong/.nvm/versions/node/v24.18.0/bin/node /home/simonfong/.nvm/ve>



# --- Phase F: Connect Claude (inside Ubuntu) ---
# Claude subscription
npm install -g @anthropic-ai/claude-code

claude auth login
# Opening browser to sign in…
# Paste code here if prompted > Login successful.

openclaw models auth login --provider anthropic --method cli --set-default
# │
# ◇

# 🦞 OpenClaw 2026.7.1-2 (0790d9f) — Open source means you can see exactly how I judge your config.

# Updated config: ~/.openclaw/openclaw.json
#   Backup: ~/.openclaw/openclaw.json.bak
# Auth profile: anthropic:claude-cli (claude-cli/oauth)
# Default model set to anthropic/claude-opus-4-8
# │
# ◇  Provider notes ────────────────────────────────────────────────────────────────────────╮
# │                                                                                         │
# │  Claude CLI auth detected; kept Anthropic model refs and selected the local Claude CLI  │
# │  runtime.                                                                               │
# │  Existing Anthropic auth profiles are kept for rollback.                                │
# │

# select model
openclaw models list --provider anthropic

# 🦞 OpenClaw 2026.7.1-2 (0790d9f)
#    Welcome to the command line: where dreams compile and confidence segfaults.

# Model                                      Input      Ctx         Local Auth  Tags
# anthropic/claude-fable-5                   text+image 1000k       no    yes
# anthropic/claude-haiku-4-5                 text+image 200k        no    yes
# anthropic/claude-haiku-4-5-20251001        text+image 200k        no    yes
# anthropic/claude-mythos-5                  text+image 1000k       no    yes
# anthropic/claude-opus-4-6                  text+image 200k        no    yes   configured
# anthropic/claude-opus-4-7                  text+image 200k        no    yes   configured
# anthropic/claude-opus-4-8                  text+image 1049k       no    yes   default,configured,alias:opus
# anthropic/claude-sonnet-4-6                text+image 200k        no    yes   configured
# anthropic/claude-sonnet-5                  text+image 1000k       no    yes   configured,alias:sonnet

openclaw config set agents.defaults.model.primary "anthropic/claude-sonnet-4-6"

systemctl --user restart openclaw-gateway

# --- Phase G: Verify ---
# 1. open question — no tools
openclaw agent --agent main --message "tell me who are you in 2 sentences."
# │
# ◇

# 🦞 OpenClaw 2026.7.1-2 (0790d9f)
#    Your .env is showing; don't worry, I'll pretend I didn't see it.

# │
# ◇
# I'm an AI assistant running inside OpenClaw, powered by Claude Sonnet 4.6 — brand new to this workspace with no name or identity established yet. You're the first person I've talked to, and I'm here to help you with whatever you need.


# 2. tool tasks — these must actually execute
openclaw agent --agent main --message "What's the weather in New York?"
# │
# ◇

# 🦞 OpenClaw 2026.7.1-2 (0790d9f) — Hot reload for config, cold sweat for deploys.

# │
# ◇
# **New York right now** (as of ~5 PM local):

# - **Overcast**, 78°F (26°C), feels like 83°F (28°C)
# - Humidity: 85% — muggy
# - Wind: 15 mph SSE
# - No precipitation

# **3-day outlook:**

# | Date | High | Low |
# |------|------|-----|
# | Today (Jul 21) | 94°F / 35°C | 67°F / 20°C |
# | Tomorrow (Jul 22) | 83°F / 29°C | 70°F / 21°C |
# | Thu (Jul 23) | 83°F / 28°C | 65°F / 18°C |

# Hot and humid today, cooling off a bit by tomorrow.

openclaw agent --agent main --message "Write and run a hello world Python program"
# │
# ◇

# 🦞 OpenClaw 2026.7.1-2 (0790d9f)
#    Your second brain, except this one actually remembers where you left things.

# │
# ◇
# Wrote and ran `hello.py` — output is `Hello, World!`.


# Phase H (Slack) is below — it has its own setup (app manifest + tokens).
```

---

## Phase H — Connect Slack

**1. Create the Slack app.** Go to <https://api.slack.com/apps/new> →
**Create New App → From a manifest** → select your workspace → paste this
manifest (Socket Mode already enabled):

```json
{
  "display_information": {
    "name": "OpenClaw",
    "description": "Slack connector for OpenClaw"
  },
  "features": {
    "bot_user": { "display_name": "OpenClaw", "always_online": true },
    "app_home": {
      "home_tab_enabled": true,
      "messages_tab_enabled": true,
      "messages_tab_read_only_enabled": false
    },
    "slash_commands": [
      {
        "command": "/openclaw",
        "description": "Send a message to OpenClaw",
        "should_escape": false
      }
    ]
  },
  "oauth_config": {
    "scopes": {
      "bot": [
        "app_mentions:read",
        "channels:history",
        "channels:read",
        "chat:write",
        "commands",
        "files:read",
        "files:write",
        "groups:history",
        "groups:read",
        "im:history",
        "im:read",
        "im:write",
        "reactions:read",
        "reactions:write",
        "users:read"
      ]
    }
  },
  "settings": {
    "socket_mode_enabled": true,
    "event_subscriptions": {
      "bot_events": [
        "app_home_opened",
        "app_mention",
        "channel_rename",
        "member_joined_channel",
        "message.channels",
        "message.groups",
        "message.im",
        "reaction_added",
        "reaction_removed"
      ]
    }
  }
}
```

**2. Generate two tokens** (Basic Information → App-Level Tokens →
`connections:write` → `xapp-…`; then Install App → Install to Workspace →
`xoxb-…`).

**3. Install the plugin + wire the config (inside Ubuntu):**

```sh
# Install the Slack channel plugin
openclaw plugins install @openclaw/slack
openclaw plugins list | grep slack        # confirm it's enabled

# Patch config to enable the slack channel in Socket Mode
cat > slack.socket.patch.json5 <<'JSON5'
{
  channels: {
    slack: {
      enabled: true,
      mode: "socket",
      appToken: { source: "env", provider: "default", id: "SLACK_APP_TOKEN" },
      botToken: { source: "env", provider: "default", id: "SLACK_BOT_TOKEN" },
    },
  },
}
JSON5
openclaw config patch --file ./slack.socket.patch.json5 --dry-run
openclaw config patch --file ./slack.socket.patch.json5
# Applied 4 config update(s). Restart the gateway to apply.
```

**4. Make the tokens visible to the systemd service** (Gotcha #1 — shell
`export` is NOT enough):

```sh
# Secrets go in the OpenClaw env file (plain KEY=value, no export/quotes)
mkdir -p ~/.config/openclaw
cat >> ~/.config/openclaw/.env <<'ENV'
SLACK_APP_TOKEN=<xapp-app-token>
SLACK_BOT_TOKEN=<xoxb-bot-token>
ENV

# Tell the systemd user service to load that env file
mkdir -p ~/.config/systemd/user/openclaw-gateway.service.d
cat > ~/.config/systemd/user/openclaw-gateway.service.d/env.conf <<'CONF'
[Service]
EnvironmentFile=%h/.config/openclaw/.env
CONF
systemctl --user daemon-reload
```

**5. Clear the crash-loop breaker with one clean foreground run** (Gotcha #2).
Earlier failed boots suppress channel autostart; a single foreground start
resets it and shows Slack connecting live:

```sh
systemctl --user stop openclaw-gateway
openclaw gateway run --force
# ...
# [slack] socket mode connected      ← success; Ctrl-C once you see this
systemctl --user start openclaw-gateway   # back to the managed service
```

**6. Let the bot answer in your channel** (Gotcha #3 — default
`groupPolicy: allowlist` silently drops channel messages):

```sh
# Simplest: answer in any channel it's invited to
openclaw config set channels.slack.groupPolicy open
# --- OR --- lock to one channel by ID (from the inbound log: C0AMCPAQYVA)
# openclaw config set channels.slack.channels.C0AMCPAQYVA.enabled true

systemctl --user restart openclaw-gateway
```

**7. Approve your Slack user + test.** In Slack, `/invite @OpenClaw` into a
channel and @-mention it. First mention returns a pairing code; approve it:

```sh
openclaw pairing approve slack <CODE>
# Approved slack sender U0AMCPAPPKN.

# also make yourself command owner (owner-only commands)
openclaw config set commands.ownerAllowFrom '["slack:U0AMCPAPPKN"]'
systemctl --user restart openclaw-gateway
```

Then @-mention with a real task — the bot replies in-thread:

- `@OpenClaw What's the weather in New York?`
- `@OpenClaw Write and run a hello world Python program`

---

## Phase I — Browser Control UI

The gateway serves a browser dashboard (chat, agents, config) on the same port
as its WebSocket: **`http://127.0.0.1:18789/`**. On WSL/localhost this works over
plain HTTP — the secure-context/HTTPS wall only applies to *remote* IPs (see
[02-aws-migration.md](02-aws-migration.md)), not this local box.

**1. Get the gateway token** (the browser tab needs it to connect):

```sh
grep -i token ~/.config/openclaw/.env
```

**2. Allow the plain-HTTP localhost session** (Control UI refuses insecure auth
by default):

```sh
openclaw config set gateway.controlUi.allowInsecureAuth true
systemctl --user restart openclaw-gateway
```

> Scope: `allowInsecureAuth` only relaxes **localhost** HTTP sessions. It does
> **not** bypass device pairing and does **not** work for remote IPs — those
> still need HTTPS.

**3. Open it from Windows.** WSL 2 forwards `localhost` to Windows, so in your
Windows browser go to:

```
http://localhost:18789/
```

Paste the **gateway token** into the dashboard's connect/settings prompt (it's
kept per browser tab, not persisted). You should land on the Control UI and be
able to chat with the `main` agent.

**If the browser can't reach it**, the gateway is likely bound to loopback
*inside* WSL only. Either bind it so Windows can reach it:

```sh
openclaw config set gateway.bind lan     # listen on the WSL VM's LAN IP too
systemctl --user restart openclaw-gateway
openclaw gateway status                   # shows the reachable URL(s)
```

then browse to `http://<wsl-ip>:18789/` (get the IP with `hostname -I`), or add a
Windows port-proxy from PowerShell (admin):

```powershell
netsh interface portproxy add v4tov4 listenport=18789 listenaddress=127.0.0.1 `
  connectport=18789 connectaddress=$(wsl hostname -I).Trim()
```

> ⚠️ Security: the Control UI HTTP surface (and the canvas host at
> `/__openclaw__/...`) is sensitive — only expose it to `localhost`/yourself,
> never to an untrusted network.

