#!/usr/bin/env bash
set -euo pipefail

: "${OPENCLAW_CONFIG_PATH:=/home/node/.openclaw/openclaw.json}"
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
envsubst < /home/node/openclaw.json.template > "$OPENCLAW_CONFIG_PATH"

echo "Starting OpenClaw gateway..."
exec openclaw gateway
