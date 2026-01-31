#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Clone openclaw source if not present
if [ ! -d "./openclaw" ]; then
  echo "==> Cloning openclaw..."
  git clone --depth 1 https://github.com/openclaw/openclaw.git ./openclaw
fi

# Create workspace dir
mkdir -p ./workspace

# Create .env from example if missing
if [ ! -f .env ]; then
  cp .env.example .env
fi

# Generate a gateway token if still using the placeholder
if grep -q "changeme" .env 2>/dev/null; then
  TOKEN=$(openssl rand -hex 32)
  sed -i.bak "s/changeme-generate-a-real-token/$TOKEN/" .env && rm -f .env.bak
  echo "Generated gateway token: $TOKEN"
fi

# Build the OpenClaw image
echo "==> Building OpenClaw image..."
docker compose build openclaw-gateway

# Start Ollama first, pull the model, then start the gateway
echo "==> Starting Ollama..."
docker compose up -d ollama

echo "==> Pulling qwen2.5-coder:32b (this will take a while on first run)..."
docker compose exec ollama ollama pull qwen2.5-coder:32b

echo "==> Running onboard wizard..."
docker compose run --rm openclaw-cli onboard --no-install-daemon

echo "==> Starting gateway..."
docker compose up -d openclaw-gateway

echo ""
echo "Done! Dashboard: http://localhost:18789/"
echo "Ollama API: http://localhost:11434/"
