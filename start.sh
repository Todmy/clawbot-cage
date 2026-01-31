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

# ── GPU detection ───────────────────────────────────────
detect_nvidia() {
  # Check for NVIDIA GPU on Linux
  if [[ "$(uname)" != "Linux" ]]; then
    return 1
  fi
  if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    return 0
  fi
  if [[ -d /proc/driver/nvidia ]] || [[ -e /dev/nvidia0 ]]; then
    return 0
  fi
  return 1
}

# ── Wizard ──────────────────────────────────────────────
run_wizard() {
  echo -e "${BOLD}${CYAN}"
  echo "┌──────────────────────────────────────────┐"
  echo "│      Clawbot Cage — Setup Wizard         │"
  echo "│      OpenClaw + Ollama (local models)    │"
  echo "└──────────────────────────────────────────┘"
  echo -e "${RESET}"

  # ── 1. Model ──────────────────────────────────────────
  header "1. Model Selection"
  info "The model determines quality, speed, and resource requirements."
  echo ""
  ask "Which model do you want to run?" \
    "qwen2.5-coder:32b    — Best coding quality (~20GB, needs 32GB+ RAM)|qwen2.5-coder:7b     — Lightweight coding (~4.5GB, runs on 8GB RAM)|llama3.3:70b          — Strong general model (~40GB, needs 64GB+ RAM)|mistral-small:24b     — Balanced quality/size (~14GB, needs 24GB+ RAM)|deepseek-coder-v2:16b — Solid coding model (~9GB, needs 16GB+ RAM)" \
    1
  MODEL_ID="${REPLY%% *}"
  ok "Model: ${MODEL_ID}"

  # ── 2. Network ────────────────────────────────────────
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

  # ── 2b. Web search (only if internet) ────────────────
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

  # ── 3. Channels (only if internet) ───────────────────
  CHANNELS=()
  CHANNEL_TOKENS=()
  if [[ "$NETWORK_MODE" == "internet" ]]; then
    header "3. Messaging Channels"
    info "Connect the bot to messaging platforms."
    info "You can skip this and add channels later."
    echo ""
    ask "Set up a messaging channel now?" \
      "Skip — configure channels later|Telegram — requires a bot token from @BotFather|Discord — requires a bot token from Discord Developer Portal|WhatsApp — scans a QR code (no token needed)" \
      1
    case "$REPLY" in
      Telegram*)
        CHANNELS+=("telegram")
        echo ""
        echo -e "  Get a token from ${BOLD}@BotFather${RESET} on Telegram:"
        echo -e "  1. Open @BotFather → /newbot → follow prompts"
        echo -e "  2. Copy the bot token"
        echo ""
        read -rp "  Telegram bot token: " tg_token
        if [[ -n "$tg_token" ]]; then
          CHANNEL_TOKENS+=("telegram:${tg_token}")
          ok "Telegram token saved"
        else
          warn "No token provided — skipping Telegram setup"
          CHANNELS=()
        fi
        ;;
      Discord*)
        CHANNELS+=("discord")
        echo ""
        echo -e "  Get a token from ${BOLD}Discord Developer Portal${RESET}:"
        echo -e "  1. https://discord.com/developers/applications → New Application"
        echo -e "  2. Bot → Reset Token → Copy"
        echo -e "  3. Enable Message Content Intent under Privileged Gateway Intents"
        echo ""
        read -rp "  Discord bot token: " dc_token
        if [[ -n "$dc_token" ]]; then
          CHANNEL_TOKENS+=("discord:${dc_token}")
          ok "Discord token saved"
        else
          warn "No token provided — skipping Discord setup"
          CHANNELS=()
        fi
        ;;
      WhatsApp*)
        CHANNELS+=("whatsapp")
        ok "WhatsApp will show a QR code after setup"
        ;;
      *)
        ok "Skipping channel setup"
        ;;
    esac
  fi

  # ── 4. Dashboard Access ──────────────────────────────
  header "4. Dashboard Access"
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

  # ── 5. Platform & GPU ───────────────────────────────
  header "5. Platform"
  PLATFORM="linux"
  ENABLE_GPU="false"

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
  elif detect_nvidia; then
    info "Detected NVIDIA GPU."
    echo ""
    ask "Enable GPU acceleration for Ollama?" \
      "Yes — use NVIDIA GPU (much faster inference)|No  — CPU only" \
      1
    case "$REPLY" in
      Yes*) ENABLE_GPU="true" ;;
      *)    ENABLE_GPU="false" ;;
    esac
  else
    info "No NVIDIA GPU detected. Using CPU inference."
    PLATFORM="linux"
  fi
  ok "Platform: ${PLATFORM}$(if [[ "$ENABLE_GPU" == "true" ]]; then echo " + NVIDIA GPU"; fi)"

  # ── Summary ───────────────────────────────────────────
  header "Summary"
  echo -e "  Model:       ${BOLD}${MODEL_ID}${RESET}"
  echo -e "  Network:     ${BOLD}${NETWORK_MODE}${RESET}"
  echo -e "  Web search:  ${BOLD}${ENABLE_SEARCH}${RESET}"
  if [[ ${#CHANNELS[@]} -gt 0 ]]; then
    echo -e "  Channel:     ${BOLD}${CHANNELS[*]}${RESET}"
  else
    echo -e "  Channel:     ${DIM}none${RESET}"
  fi
  echo -e "  Dashboard:   ${BOLD}${BIND_HOST}${RESET}"
  echo -e "  GPU:         ${BOLD}${ENABLE_GPU}${RESET}"
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
ENABLE_GPU=${ENABLE_GPU}
EOF
  ok "Written .env (token: ${TOKEN:0:8}...)"

  # ── openclaw.json ─────────────────────────────────
  local OLLAMA_URL="http://ollama:11434/v1"
  if [[ "$PLATFORM" == "macos-native" ]]; then
    OLLAMA_URL="http://host.docker.internal:11434/v1"
  fi

  local SKILLS_BLOCK=""
  if [[ "$ENABLE_SEARCH" == "false" ]]; then
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
}

# ── Compose command builder ─────────────────────────────
# Builds the correct docker compose command with all overlays
compose_cmd() {
  local -a cmd=(docker compose -f docker-compose.yml)
  if [[ "$NETWORK_MODE" == "internet" ]]; then
    cmd+=(-f docker-compose.internet.yml)
  fi
  if [[ "$ENABLE_GPU" == "true" ]]; then
    cmd+=(-f docker-compose.gpu.yml)
  fi
  "${cmd[@]}" "$@"
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
  compose_cmd build openclaw-gateway

  # Build sandbox image if the script exists
  if [ -f "$OPENCLAW_DIR/scripts/sandbox-setup.sh" ]; then
    header "Building sandbox image..."
    (cd "$OPENCLAW_DIR" && bash scripts/sandbox-setup.sh)
  fi

  # Start Ollama (unless native macOS)
  if [[ "$PLATFORM" != "macos-native" ]]; then
    header "Starting Ollama..."
    compose_cmd up -d ollama

    header "Pulling ${MODEL_ID} (this will take a while on first run)..."
    compose_cmd --profile setup run --rm ollama-pull
  else
    header "Native Ollama mode"
    echo "Ensure Ollama is running: ollama serve"
    echo "Pull the model if needed: ollama pull ${MODEL_ID}"
    echo ""
    read -rp "Press Enter when Ollama is ready..."
  fi

  # Run onboard wizard
  header "Running OpenClaw onboard wizard..."
  compose_cmd --profile cli run --rm openclaw-cli onboard --no-install-daemon

  # ── Channel setup ─────────────────────────────────
  if [[ ${#CHANNELS[@]} -gt 0 ]]; then
    header "Setting up channels..."
    for channel in "${CHANNELS[@]}"; do
      case "$channel" in
        whatsapp)
          echo "Scanning WhatsApp QR code..."
          compose_cmd --profile cli run --rm openclaw-cli channels login
          ;;
        telegram)
          for ct in "${CHANNEL_TOKENS[@]}"; do
            if [[ "$ct" == telegram:* ]]; then
              local token="${ct#telegram:}"
              compose_cmd --profile cli run --rm openclaw-cli channels add --channel telegram --token "$token"
              ok "Telegram channel added"
            fi
          done
          ;;
        discord)
          for ct in "${CHANNEL_TOKENS[@]}"; do
            if [[ "$ct" == discord:* ]]; then
              local token="${ct#discord:}"
              compose_cmd --profile cli run --rm openclaw-cli channels add --channel discord --token "$token"
              ok "Discord channel added"
            fi
          done
          ;;
      esac
    done
  fi

  # Start the gateway
  header "Starting gateway..."
  compose_cmd up -d openclaw-gateway

  # ── Done ──────────────────────────────────────────
  echo ""
  echo -e "${BOLD}${GREEN}┌──────────────────────────────────────────┐${RESET}"
  echo -e "${BOLD}${GREEN}│           Setup complete!                │${RESET}"
  echo -e "${BOLD}${GREEN}└──────────────────────────────────────────┘${RESET}"
  echo ""
  echo -e "  Dashboard:  ${BOLD}http://localhost:18789/${RESET}"
  echo -e "  Network:    ${BOLD}${NETWORK_MODE}${RESET}"
  echo -e "  Model:      ${BOLD}${MODEL_ID}${RESET}"
  if [[ "$ENABLE_GPU" == "true" ]]; then
    echo -e "  GPU:        ${BOLD}NVIDIA enabled${RESET}"
  fi
  if [[ ${#CHANNELS[@]} -gt 0 ]]; then
    echo -e "  Channels:   ${BOLD}${CHANNELS[*]}${RESET}"
  fi

  if [[ "$NETWORK_MODE" == "isolated" ]]; then
    echo ""
    info "To enable internet later:"
    info "  docker compose -f docker-compose.yml -f docker-compose.internet.yml up -d openclaw-gateway"
  fi

  echo ""
  echo -e "  Logs:       docker compose logs -f openclaw-gateway"
  echo -e "  Stop:       docker compose down"
  echo -e "  Rerun:      ./start.sh"
  echo ""
}

# ── Main ────────────────────────────────────────────────
# Allow non-interactive mode with env vars
if [[ "${CLAWBOT_NON_INTERACTIVE:-}" == "1" ]]; then
  MODEL_ID="${OLLAMA_MODEL:-qwen2.5-coder:32b}"
  NETWORK_MODE="${NETWORK_MODE:-isolated}"
  ENABLE_SEARCH="${ENABLE_SEARCH:-false}"
  ENABLE_GPU="${ENABLE_GPU:-false}"
  BIND_MODE="${OPENCLAW_GATEWAY_BIND:-loopback}"
  BIND_HOST="127.0.0.1"
  [[ "$BIND_MODE" == "lan" ]] && BIND_HOST="0.0.0.0"
  PLATFORM="docker"
  [[ "$(uname)" == "Darwin" ]] && PLATFORM="docker"
  CHANNELS=()
  CHANNEL_TOKENS=()
else
  run_wizard
fi

write_config
build_and_start
