#!/usr/bin/env bash
set -euo pipefail

# Use /data for Balena persistent storage, fallback for local dev
: "${OPENCLAW_CONFIG_PATH:=/data/openclaw/openclaw.json}"
: "${OPENCLAW_CONTROLUI_ALLOW_INSECURE_AUTH:=true}"
export OPENCLAW_CONTROLUI_ALLOW_INSECURE_AUTH
STATE_DIR="$(dirname "$OPENCLAW_CONFIG_PATH")"
mkdir -p "$STATE_DIR"

# Ensure gateway token exists (OpenClaw config will fail if env var is missing/empty)
if [ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
  TOKEN_FILE="$STATE_DIR/gateway.token"
  if [ -f "$TOKEN_FILE" ]; then
    export OPENCLAW_GATEWAY_TOKEN="$(cat "$TOKEN_FILE")"
  else
    export OPENCLAW_GATEWAY_TOKEN="$(node -e 'console.log(require("crypto").randomBytes(32).toString("hex"))')"
    echo -n "$OPENCLAW_GATEWAY_TOKEN" > "$TOKEN_FILE"
  fi
  echo "Gateway token: $OPENCLAW_GATEWAY_TOKEN"
fi

# Only render config from template if it doesn't exist (preserve wizard settings)
if [ ! -f "$OPENCLAW_CONFIG_PATH" ]; then
  echo "Rendering initial config from template..."
  envsubst < /app/openclaw.json5.template > "$OPENCLAW_CONFIG_PATH"
else
  echo "Using existing config at $OPENCLAW_CONFIG_PATH"
fi

# Auto-configure API keys in ~/.openclaw/.env (OpenClaw reads keys from here)
OPENCLAW_ENV_FILE="/root/.openclaw/.env"
mkdir -p "$(dirname "$OPENCLAW_ENV_FILE")"

# Helper function to check if a variable has actual content (not placeholders)
has_value() {
  local val="$1"
  val="${val//[[:space:]]/}"
  [ -n "$val" ] && [[ ! "$val" =~ ^\$\{ ]]
}

GOOGLE_KEY="${GOOGLE_API_KEY:-}"
OPENAI_KEY="${OPENAI_API_KEY:-}"
ANTHROPIC_KEY="${ANTHROPIC_API_KEY:-}"
OPENROUTER_KEY="${OPENROUTER_API_KEY:-}"

if has_value "$GOOGLE_KEY" || has_value "$OPENAI_KEY" || has_value "$ANTHROPIC_KEY" || has_value "$OPENROUTER_KEY"; then
  echo "Configuring API keys in $OPENCLAW_ENV_FILE..."
  > "$OPENCLAW_ENV_FILE"

  if has_value "$GOOGLE_KEY"; then
    echo "GOOGLE_API_KEY=$GOOGLE_KEY" >> "$OPENCLAW_ENV_FILE"
    echo "  - Google API key configured"
  fi
  if has_value "$OPENAI_KEY"; then
    echo "OPENAI_API_KEY=$OPENAI_KEY" >> "$OPENCLAW_ENV_FILE"
    echo "  - OpenAI API key configured"
  fi
  if has_value "$ANTHROPIC_KEY"; then
    echo "ANTHROPIC_API_KEY=$ANTHROPIC_KEY" >> "$OPENCLAW_ENV_FILE"
    echo "  - Anthropic API key configured"
  fi
  if has_value "$OPENROUTER_KEY"; then
    echo "OPENROUTER_API_KEY=$OPENROUTER_KEY" >> "$OPENCLAW_ENV_FILE"
    echo "  - OpenRouter API key configured"
  fi
fi

echo "Starting OpenClaw gateway..."
exec openclaw gateway --bind lan
