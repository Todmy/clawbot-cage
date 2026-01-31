#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

OPENCLAW_DIR="./openclaw"

# Clone openclaw source if not present
if [ ! -d "$OPENCLAW_DIR" ]; then
  echo "==> Cloning openclaw..."
  git clone --depth 1 https://github.com/openclaw/openclaw.git "$OPENCLAW_DIR"
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

# Build sandbox image if the script exists
if [ -f "$OPENCLAW_DIR/scripts/sandbox-setup.sh" ]; then
  echo "==> Building sandbox image..."
  (cd "$OPENCLAW_DIR" && bash scripts/sandbox-setup.sh)
fi

# Start Ollama
echo "==> Starting Ollama..."
docker compose up -d ollama

# Pull the model via the temporary setup service (has internet access)
echo "==> Pulling model (this will take a while on first run)..."
docker compose --profile setup run --rm ollama-pull

# Run onboard wizard (CLI needs rw config access)
echo "==> Running onboard wizard..."
docker compose --profile cli run --rm openclaw-cli onboard --no-install-daemon

# Start the gateway
echo "==> Starting gateway..."
docker compose up -d openclaw-gateway

echo ""
echo "Done! Dashboard: http://localhost:18789/"
echo ""
echo "Network mode: ISOLATED (no internet)."
echo "To enable internet access for the gateway:"
echo "  docker compose -f docker-compose.yml -f docker-compose.internet.yml up -d openclaw-gateway"
