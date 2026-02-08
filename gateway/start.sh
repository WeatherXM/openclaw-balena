#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# OpenClaw Balena – start script
# ---------------------------------------------------------------------------
# 1. Runtime version update  (OPENCLAW_VERSION env var)
# 2. Token management        (OPENCLAW_GATEWAY_TOKEN)
# 3. Config rendering        (JSON5 template → openclaw.json)
# 4. API-key injection       (provider keys → ~/.openclaw/.env)
# 5. Skills installation     (OPENCLAW_SKILLS env var)
# 6. Plugins installation    (OPENCLAW_PLUGINS env var)
# 7. Launch gateway
# ---------------------------------------------------------------------------

# ── Helpers ────────────────────────────────────────────────────────────────

# Check if a variable has actual content (not empty / unresolved placeholder).
# Balena may pass literal "${VAR:-}" when a device variable is not set.
has_value() {
  local val="$1"
  val="${val//[[:space:]]/}"
  [ -n "$val" ] && [[ ! "$val" =~ \$\{ ]]
}

# Return the value only if it has actual content, empty string otherwise.
clean_var() {
  local val="$1"
  if has_value "$val"; then echo "$val"; else echo ""; fi
}

# ── Directories & defaults ────────────────────────────────────────────────

# Use /data for Balena persistent storage, fallback for local dev
: "${OPENCLAW_CONFIG_PATH:=/data/openclaw/openclaw.json}"
: "${OPENCLAW_CONTROLUI_ALLOW_INSECURE_AUTH:=true}"
export OPENCLAW_CONTROLUI_ALLOW_INSECURE_AUTH
STATE_DIR="$(dirname "$OPENCLAW_CONFIG_PATH")"
mkdir -p "$STATE_DIR"

# ── 1. Runtime OpenClaw version management ────────────────────────────────
#
# If OPENCLAW_VERSION is set and differs from what's currently installed,
# upgrade (or downgrade) in-place.  The new binary lands in the global
# node_modules and takes effect immediately.
#
DESIRED_VERSION="$(clean_var "${OPENCLAW_VERSION:-}")"
if [ -n "$DESIRED_VERSION" ]; then
  # Get currently installed version
  CURRENT_VERSION="$(openclaw --version 2>/dev/null | head -1 || echo "unknown")"

  if [ "$CURRENT_VERSION" != "$DESIRED_VERSION" ]; then
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║  OpenClaw version change detected                           ║"
    echo "║  Current : ${CURRENT_VERSION}"
    echo "║  Target  : ${DESIRED_VERSION}"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo "Installing openclaw@${DESIRED_VERSION} ..."
    if npm install -g "openclaw@${DESIRED_VERSION}"; then
      NEW_VERSION="$(openclaw --version 2>/dev/null | head -1 || echo "unknown")"
      echo "✓ OpenClaw updated to ${NEW_VERSION}"
    else
      echo "⚠ Failed to install openclaw@${DESIRED_VERSION} – continuing with ${CURRENT_VERSION}"
    fi
  else
    echo "OpenClaw ${CURRENT_VERSION} already matches requested version."
  fi
else
  CURRENT_VERSION="$(openclaw --version 2>/dev/null | head -1 || echo "unknown")"
  echo "OpenClaw version: ${CURRENT_VERSION} (no OPENCLAW_VERSION override set)"
fi

# ── 2. Ensure gateway token exists ────────────────────────────────────────
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

# ── 3. Render config from template on first run ──────────────────────────
if [ ! -f "$OPENCLAW_CONFIG_PATH" ]; then
  echo "Rendering initial config from template..."
  envsubst < /app/openclaw.json5.template > "$OPENCLAW_CONFIG_PATH"
else
  echo "Using existing config at $OPENCLAW_CONFIG_PATH"
fi

# ── 4. Auto-configure API keys ───────────────────────────────────────────
OPENCLAW_ENV_FILE="/root/.openclaw/.env"
mkdir -p "$(dirname "$OPENCLAW_ENV_FILE")"

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

# ── 5. Install skills from OPENCLAW_SKILLS ───────────────────────────────
#
# Comma-separated list of ClawHub skill slugs.
# Example: OPENCLAW_SKILLS="home-assistant,web-search,coding-patterns"
#
# Skills are installed to ~/.openclaw/skills/ (persistent volume).
# Already-installed skills are re-checked (fast no-op on second boot).
#
SKILLS_LIST="$(clean_var "${OPENCLAW_SKILLS:-}")"
if [ -n "$SKILLS_LIST" ]; then
  echo "──────────────────────────────────────────────────────────────────"
  echo "  Installing skills: ${SKILLS_LIST}"
  echo "──────────────────────────────────────────────────────────────────"
  IFS=',' read -ra SKILLS <<< "$SKILLS_LIST"
  for skill in "${SKILLS[@]}"; do
    skill="$(echo "$skill" | xargs)"  # trim whitespace
    [ -z "$skill" ] && continue
    echo "  → Installing skill: ${skill} ..."
    if openclaw skills install "$skill" 2>&1; then
      echo "    ✓ ${skill} installed"
    else
      echo "    ⚠ Failed to install skill: ${skill} (continuing)"
    fi
  done
fi

# ── 6. Install plugins from OPENCLAW_PLUGINS ─────────────────────────────
#
# Comma-separated list of plugin npm packages or local paths.
# Example: OPENCLAW_PLUGINS="@openclaw/voice-call,@openclaw/homebridge"
#
# Plugins are installed to ~/.openclaw/extensions/ (persistent volume).
#
PLUGINS_LIST="$(clean_var "${OPENCLAW_PLUGINS:-}")"
if [ -n "$PLUGINS_LIST" ]; then
  echo "──────────────────────────────────────────────────────────────────"
  echo "  Installing plugins: ${PLUGINS_LIST}"
  echo "──────────────────────────────────────────────────────────────────"
  IFS=',' read -ra PLUGINS <<< "$PLUGINS_LIST"
  for plugin in "${PLUGINS[@]}"; do
    plugin="$(echo "$plugin" | xargs)"  # trim whitespace
    [ -z "$plugin" ] && continue
    echo "  → Installing plugin: ${plugin} ..."
    if openclaw plugins install "$plugin" 2>&1; then
      echo "    ✓ ${plugin} installed"
    else
      echo "    ⚠ Failed to install plugin: ${plugin} (continuing)"
    fi
  done
fi

# ── 7. Launch the gateway ─────────────────────────────────────────────────
echo ""
echo "Starting OpenClaw gateway..."
exec openclaw gateway --bind lan
