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

# Render config from template using envsubst (substitutes ${VAR} placeholders)
echo "Rendering config from template..."
envsubst < /app/openclaw.json5.template > "$OPENCLAW_CONFIG_PATH"

echo "Starting OpenClaw gateway..."
exec openclaw gateway --bind lan
