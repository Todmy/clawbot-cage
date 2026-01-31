# Clawbot Cage — OpenClaw + Ollama (Docker Compose)

Run [OpenClaw](https://github.com/openclaw/openclaw) with fully local open-source models via Ollama. No API keys, no cloud dependencies. One command to start.

**Default model:** Qwen 2.5 Coder 32B (~20GB download, ~20GB VRAM or CPU fallback)

## Prerequisites

- Git
- Docker and Docker Compose v2+
- ~25GB disk for the model + ~5GB for the OpenClaw image
- 32GB+ RAM recommended (CPU inference) or NVIDIA GPU with 20GB+ VRAM

## Quick Start

```bash
git clone git@github.com:Todmy/clawbot-cage.git
cd clawbot-cage
./start.sh
```

The script will:
1. Clone the OpenClaw source into `./openclaw/`
2. Generate a secure gateway token in `.env`
3. Build the OpenClaw Docker image
4. Start Ollama and pull `qwen2.5-coder:32b`
5. Run the interactive onboard wizard
6. Start the gateway

Dashboard: http://localhost:18789/

## Manual Setup

```bash
# 1. Clone OpenClaw source (build context)
git clone --depth 1 https://github.com/openclaw/openclaw.git ./openclaw

# 2. Build the image
docker compose build openclaw-gateway

# 3. Start Ollama
docker compose up -d ollama

# 4. Pull the model (first run only)
docker compose exec ollama ollama pull qwen2.5-coder:32b

# 5. Run onboard wizard
docker compose run --rm openclaw-cli onboard --no-install-daemon

# 6. Start the gateway
docker compose up -d openclaw-gateway
```

## Project Structure

```
clawbot-cage/
├── .env                    # Env vars (token, ports) — auto-generated on first run
├── docker-compose.yml      # All services: Ollama + OpenClaw gateway + CLI
├── config/
│   └── openclaw.json       # OpenClaw config (model, provider, gateway settings)
├── workspace/              # Agent workspace (created on first run)
├── start.sh                # One-shot setup and launch script
├── SETUP.md                # This file
└── openclaw/               # Cloned OpenClaw source (git-ignored, used as build context)
```

## Configuration

### .env

| Variable | Default | Description |
|---|---|---|
| `OPENCLAW_GATEWAY_TOKEN` | auto-generated | Auth token for gateway access |
| `OPENCLAW_GATEWAY_PORT` | `18789` | Gateway HTTP/WS port |
| `OPENCLAW_BRIDGE_PORT` | `18790` | Bridge port |
| `OPENCLAW_GATEWAY_BIND` | `lan` | Bind mode: `loopback`, `lan`, `tailnet` |

### Switching Models

Edit `config/openclaw.json` — change the model ID in three places:

1. `agents.defaults.model.primary`
2. `agents.defaults.models` (allowlist entry)
3. `models.providers.ollama.models[0].id`

Then pull the new model and restart:

```bash
docker compose exec ollama ollama pull <model-name>
docker compose restart openclaw-gateway
```

Popular alternatives:

| Model | Ollama ID | Size | Notes |
|---|---|---|---|
| Qwen 2.5 Coder 7B | `qwen2.5-coder:7b` | ~4.5GB | Lightweight, 8GB VRAM enough |
| Llama 3.3 70B | `llama3.3:70b` | ~40GB | Strong general model |
| Mistral Small 24B | `mistral-small:24b` | ~14GB | Good balance |
| DeepSeek Coder V2 | `deepseek-coder-v2:16b` | ~9GB | Solid coding model |

### GPU Support (Linux + NVIDIA)

Uncomment the GPU section in `docker-compose.yml` under the `ollama` service:

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu]
```

Requires [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html).

### macOS (Apple Silicon)

Ollama in Docker has **no GPU access** on macOS. For usable performance, run Ollama natively:

1. Install: `brew install ollama`
2. Start: `ollama serve`
3. Pull model: `ollama pull qwen2.5-coder:32b`
4. In `config/openclaw.json`, change `baseUrl` to:
   ```
   http://host.docker.internal:11434/v1
   ```
5. Comment out the `ollama` service in `docker-compose.yml`
6. Start: `docker compose up -d openclaw-gateway`

This uses the Metal GPU backend for inference.

## Adding Channels

```bash
# WhatsApp (QR code scan)
docker compose run --rm openclaw-cli channels login

# Telegram
docker compose run --rm openclaw-cli channels add --channel telegram --token "<bot-token>"

# Discord
docker compose run --rm openclaw-cli channels add --channel discord --token "<bot-token>"
```

## Common Commands

```bash
# View logs
docker compose logs -f openclaw-gateway

# Restart after config change
docker compose restart openclaw-gateway

# Stop everything
docker compose down

# Stop and remove all data (models, workspace)
docker compose down -v

# List loaded models
docker compose exec ollama ollama list

# Pull additional model
docker compose exec ollama ollama pull <model>

# Health check
docker compose exec openclaw-gateway node dist/index.mjs health --token "$OPENCLAW_GATEWAY_TOKEN"
```

## Troubleshooting

**Gateway won't start / config validation error:**
```bash
docker compose run --rm openclaw-cli doctor
docker compose run --rm openclaw-cli doctor --fix
```

**Model not responding:**
```bash
# Verify Ollama is serving
curl http://localhost:11434/v1/models

# Check loaded models
docker compose exec ollama ollama list
```

**Out of memory:** Switch to a smaller model (see table above).

**Slow inference on macOS Docker:** Use native Ollama (see macOS section).

## License

This configuration overlay is MIT. OpenClaw itself is [MIT licensed](https://github.com/openclaw/openclaw/blob/main/LICENSE).
