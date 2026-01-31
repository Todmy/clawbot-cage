#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

OPENCLAW_DIR="./openclaw"

# ── Colors ──────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

header() { echo -e "\n${BOLD}${CYAN}$1${RESET}"; }
info()   { echo -e "${DIM}$1${RESET}"; }
warn()   { echo -e "${YELLOW}⚠ $1${RESET}"; }
ok()     { echo -e "${GREEN}✓ $1${RESET}"; }

# ── Prompt helper ───────────────────────────────────────
# Usage: ask "Question" "opt1|opt2|opt3" DEFAULT_INDEX
# Returns the selected option in $REPLY
ask() {
  local question="$1"
  IFS='|' read -ra opts <<< "$2"
  local default="${3:-1}"

  echo -e "\n${BOLD}${question}${RESET}"
  for i in "${!opts[@]}"; do
    local num=$((i + 1))
    if [[ $num -eq $default ]]; then
      echo -e "  ${GREEN}${num})${RESET} ${opts[$i]} ${DIM}(default)${RESET}"
    else
      echo -e "  ${num}) ${opts[$i]}"
    fi
  done

  while true; do
    read -rp "Choose [${default}]: " choice
    choice="${choice:-$default}"
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#opts[@]} )); then
      REPLY="${opts[$((choice - 1))]}"
      return
    fi
    echo "  Invalid choice. Enter 1-${#opts[@]}."
  done
}

# ── Wizard ──────────────────────────────────────────────
run_wizard() {
  echo -e "${BOLD}${CYAN}"
  echo "┌─────────────────────────────────────────┐"
  echo "│     Clawbot Cage — Setup Wizard          │"
  echo "│     OpenClaw + Ollama (local models)     │"
  echo "└─────────────────────────────────────────┘"
  echo -e "${RESET}"

  # ── Model ───────────────────────────────────────────
  header "1. Model Selection"
  info "The model determines quality, speed, and resource requirements."
  echo ""
  ask "Which model do you want to run?" \
    "qwen2.5-coder:32b   — Best coding quality (~20GB, needs 32GB+ RAM)|qwen2.5-coder:7b    — Lightweight coding (~4.5GB, runs on 8GB RAM)|llama3.3:70b         — Strong general model (~40GB, needs 64GB+ RAM)|mistral-small:24b    — Balanced quality/size (~14GB, needs 24GB+ RAM)|deepseek-coder-v2:16b — Solid coding model (~9GB, needs 16GB+ RAM)" \
    1
  # Extract the model ID (everything before the first space)
  MODEL_ID="${REPLY%% *}"
  ok "Model: ${MODEL_ID}"

  # ── Network ─────────────────────────────────────────
  header "2. Network Mode"
  info "Controls whether the bot can access the internet."
  echo ""
  echo -e "  ${BOLD}Isolated${RESET}  — No internet. Dashboard only. Most secure."
  echo -e "  ${BOLD}Internet${RESET}  — Outbound access for channels (Telegram, Discord, etc)."
  echo -e "            Agent tool execution stays sandboxed (no network) regardless."
  echo ""
  ask "Network mode?" \
    "Isolated (no internet, dashboard only)|Internet (required for messaging channels)" \
    1
  case "$REPLY" in
    Isolated*) NETWORK_MODE="isolated" ;;
    *)         NETWORK_MODE="internet" ;;
  esac
  ok "Network: ${NETWORK_MODE}"

  # ── Web search (only if internet) ──────────────────
  ENABLE_SEARCH="false"
  if [[ "$NETWORK_MODE" == "internet" ]]; then
    header "2b. Web Search"
    info "Allow the agent to search the web and fetch URLs."
    info "This uses the gateway's internet connection (not the sandbox)."
    echo ""
    ask "Enable web search skills?" \
      "No  — Agent cannot search the web (safer)|Yes — Agent can search and fetch URLs" \
      1
    case "$REPLY" in
      Yes*) ENABLE_SEARCH="true" ;;
      *)    ENABLE_SEARCH="false" ;;
    esac
    ok "Web search: ${ENABLE_SEARCH}"
  fi

  # ── Access ──────────────────────────────────────────
  header "3. Dashboard Access"
  info "Who can reach the dashboard and API."
  echo ""
  ask "Bind the dashboard to?" \
    "Localhost only (127.0.0.1) — only this machine|LAN (0.0.0.0) — accessible from other devices on your network" \
    1
  case "$REPLY" in
    Localhost*) BIND_MODE="loopback"; BIND_HOST="127.0.0.1" ;;
    *)          BIND_MODE="lan"; BIND_HOST="0.0.0.0"
                warn "LAN mode: ensure your gateway token is strong." ;;
  esac
  ok "Bind: ${BIND_HOST}"

  # ── Platform hint ───────────────────────────────────
  header "4. Platform"
  PLATFORM="linux"
  if [[ "$(uname)" == "Darwin" ]]; then
    info "Detected macOS."
    echo ""
    ask "How do you want to run Ollama?" \
      "Docker (CPU only, slower on Mac)|Native (brew install ollama — uses Metal GPU, much faster)" \
      2
    case "$REPLY" in
      Native*) PLATFORM="macos-native" ;;
      *)       PLATFORM="docker" ;;
    esac
  fi
  ok "Platform: ${PLATFORM}"

  # ── Summary ─────────────────────────────────────────
  header "Summary"
  echo -e "  Model:       ${BOLD}${MODEL_ID}${RESET}"
  echo -e "  Network:     ${BOLD}${NETWORK_MODE}${RESET}"
  echo -e "  Web search:  ${BOLD}${ENABLE_SEARCH}${RESET}"
  echo -e "  Dashboard:   ${BOLD}${BIND_HOST}${RESET}"
  echo -e "  Platform:    ${BOLD}${PLATFORM}${RESET}"
  echo ""
  read -rp "Proceed with this configuration? [Y/n]: " confirm
  if [[ "${confirm,,}" == "n" ]]; then
    echo "Aborted."
    exit 0
  fi
}

# ── Write config files ─────────────────────────────────
write_config() {
  mkdir -p ./config ./workspace

  # ── .env ──────────────────────────────────────────
  local TOKEN
  if [[ -f .env ]] && ! grep -q "changeme" .env; then
    # Preserve existing token
    TOKEN=$(grep OPENCLAW_GATEWAY_TOKEN .env | cut -d= -f2)
  else
    TOKEN=$(openssl rand -hex 32)
  fi

  cat > .env <<EOF
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_BRIDGE_PORT=18790
OPENCLAW_GATEWAY_BIND=${BIND_MODE}
OPENCLAW_BIND_HOST=${BIND_HOST}
OPENCLAW_GATEWAY_TOKEN=${TOKEN}
OLLAMA_MODEL=${MODEL_ID}
NETWORK_MODE=${NETWORK_MODE}
EOF
  ok "Written .env (token: ${TOKEN:0:8}...)"

  # ── openclaw.json ─────────────────────────────────
  # Determine baseUrl based on platform
  local OLLAMA_URL="http://ollama:11434/v1"
  if [[ "$PLATFORM" == "macos-native" ]]; then
    OLLAMA_URL="http://host.docker.internal:11434/v1"
  fi

  # Build skills config
  local SKILLS_BLOCK=""
  if [[ "$ENABLE_SEARCH" == "false" ]]; then
    # Deny web-related skills
    SKILLS_BLOCK='
  skills: {
    allowBundled: []
  },'
  fi

  cat > ./config/openclaw.json <<EOF
{
  // Gateway
  gateway: {
    port: 18789,
    controlUi: { enabled: true }
  },
${SKILLS_BLOCK}
  // Agent config
  agents: {
    defaults: {
      workspace: "~/.openclaw/workspace",
      model: {
        primary: "ollama/${MODEL_ID}"
      },
      models: {
        "ollama/${MODEL_ID}": { alias: "Local Model" }
      },

      // Sandbox: tool execution runs in isolated throwaway containers
      sandbox: {
        mode: "non-main",
        scope: "agent",
        workspaceAccess: "rw",
        docker: {
          image: "openclaw-sandbox:bookworm-slim",
          readOnlyRoot: true,
          network: "none",
          user: "1000:1000",
          capDrop: ["ALL"]
        }
      }
    }
  },

  // Custom provider: Ollama
  models: {
    mode: "merge",
    providers: {
      ollama: {
        baseUrl: "${OLLAMA_URL}",
        apiKey: "ollama",
        api: "openai-responses",
        models: [
          {
            id: "${MODEL_ID}",
            name: "${MODEL_ID}",
            reasoning: false,
            input: ["text"],
            cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
            contextWindow: 32768,
            maxTokens: 8192
          }
        ]
      }
    }
  }
}
EOF
  ok "Written config/openclaw.json"

  # ── Update port bindings in docker-compose.yml ────
  # Handled via BIND_HOST in .env and compose interpolation
}

# ── Build & start ──────────────────────────────────────
build_and_start() {
  # Clone openclaw source if not present
  if [ ! -d "$OPENCLAW_DIR" ]; then
    header "Cloning OpenClaw source..."
    git clone --depth 1 https://github.com/openclaw/openclaw.git "$OPENCLAW_DIR"
  fi

  # Build the OpenClaw image
  header "Building OpenClaw image..."
  docker compose build openclaw-gateway

  # Build sandbox image if the script exists
  if [ -f "$OPENCLAW_DIR/scripts/sandbox-setup.sh" ]; then
    header "Building sandbox image..."
    (cd "$OPENCLAW_DIR" && bash scripts/sandbox-setup.sh)
  fi

  # Start Ollama (unless native macOS)
  if [[ "$PLATFORM" != "macos-native" ]]; then
    header "Starting Ollama..."
    docker compose up -d ollama

    header "Pulling ${MODEL_ID} (this will take a while on first run)..."
    docker compose --profile setup run --rm ollama-pull
  else
    header "Native Ollama mode"
    echo "Ensure Ollama is running: ollama serve"
    echo "Pull the model if needed: ollama pull ${MODEL_ID}"
    echo ""
    read -rp "Press Enter when Ollama is ready..."
  fi

  # Run onboard wizard
  header "Running OpenClaw onboard wizard..."
  docker compose --profile cli run --rm openclaw-cli onboard --no-install-daemon

  # Start the gateway (with or without internet)
  header "Starting gateway..."
  if [[ "$NETWORK_MODE" == "internet" ]]; then
    docker compose -f docker-compose.yml -f docker-compose.internet.yml up -d openclaw-gateway
  else
    docker compose up -d openclaw-gateway
  fi

  echo ""
  echo -e "${BOLD}${GREEN}┌─────────────────────────────────────────┐${RESET}"
  echo -e "${BOLD}${GREEN}│          Setup complete!                 │${RESET}"
  echo -e "${BOLD}${GREEN}└─────────────────────────────────────────┘${RESET}"
  echo ""
  echo -e "  Dashboard:  ${BOLD}http://localhost:18789/${RESET}"
  echo -e "  Network:    ${BOLD}${NETWORK_MODE}${RESET}"
  echo -e "  Model:      ${BOLD}${MODEL_ID}${RESET}"

  if [[ "$NETWORK_MODE" == "isolated" ]]; then
    echo ""
    info "To enable internet later:"
    info "  docker compose -f docker-compose.yml -f docker-compose.internet.yml up -d openclaw-gateway"
  fi

  echo ""
  echo -e "  Logs:       docker compose logs -f openclaw-gateway"
  echo -e "  Stop:       docker compose down"
  echo ""
}

# ── Main ────────────────────────────────────────────────
# Allow non-interactive mode with env vars
if [[ "${CLAWBOT_NON_INTERACTIVE:-}" == "1" ]]; then
  MODEL_ID="${OLLAMA_MODEL:-qwen2.5-coder:32b}"
  NETWORK_MODE="${NETWORK_MODE:-isolated}"
  ENABLE_SEARCH="${ENABLE_SEARCH:-false}"
  BIND_MODE="${OPENCLAW_GATEWAY_BIND:-loopback}"
  BIND_HOST="127.0.0.1"
  [[ "$BIND_MODE" == "lan" ]] && BIND_HOST="0.0.0.0"
  PLATFORM="docker"
  [[ "$(uname)" == "Darwin" ]] && PLATFORM="docker"
else
  run_wizard
fi

write_config
build_and_start
