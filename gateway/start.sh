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

# Extract bare semver-ish version from a string like "openclaw version 1.2.3"
# or "openclaw/1.2.3-4". Returns just the "1.2.3-4" part.
extract_version() {
  echo "$1" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+([-.][0-9a-zA-Z]+)*' | head -1
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

# Persistent npm prefix – survives container restarts
NPM_PERSIST_DIR="/data/openclaw/npm-global"
mkdir -p "$NPM_PERSIST_DIR"
# Prepend persistent bin dir so runtime-installed openclaw takes priority
export PATH="${NPM_PERSIST_DIR}/bin:${PATH}"

# ── 1. Runtime OpenClaw version management ────────────────────────────────
#
# If OPENCLAW_VERSION is set and differs from what's currently installed,
# upgrade (or downgrade) in-place.  The new binary lands in the global
# node_modules and takes effect immediately.
#
DESIRED_VERSION="$(clean_var "${OPENCLAW_VERSION:-}")"
# Strip leading "v" if present (e.g. "v2026.2.13" → "2026.2.13")
DESIRED_VERSION="${DESIRED_VERSION#v}"
if [ -n "$DESIRED_VERSION" ]; then
  # Get currently installed version (extract bare version number)
  RAW_VERSION="$(openclaw --version 2>/dev/null | head -1 || echo "unknown")"
  CURRENT_VERSION="$(extract_version "$RAW_VERSION")"
  CURRENT_VERSION="${CURRENT_VERSION:-unknown}"
  echo "Installed version raw output: '${RAW_VERSION}' → parsed: '${CURRENT_VERSION}'"
  echo "Requested version: '${DESIRED_VERSION}'"

  if [ "$CURRENT_VERSION" != "$DESIRED_VERSION" ]; then
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║  OpenClaw version change detected                           ║"
    echo "║  Current : ${CURRENT_VERSION}"
    echo "║  Target  : ${DESIRED_VERSION}"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo "Installing openclaw@${DESIRED_VERSION} to ${NPM_PERSIST_DIR} ..."
    if npm install -g --prefix "$NPM_PERSIST_DIR" --loglevel verbose "openclaw@${DESIRED_VERSION}"; then
      NEW_VERSION="$(extract_version "$(openclaw --version 2>/dev/null | head -1)")"
      echo "✓ OpenClaw updated to ${NEW_VERSION:-unknown}"
    else
      echo "⚠ Failed to install openclaw@${DESIRED_VERSION} – continuing with ${CURRENT_VERSION}"
    fi
  else
    echo "OpenClaw ${CURRENT_VERSION} already matches requested version."
  fi
else
  CURRENT_VERSION="$(extract_version "$(openclaw --version 2>/dev/null | head -1)")"
  echo "OpenClaw version: ${CURRENT_VERSION:-unknown} (no OPENCLAW_VERSION override set)"
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

# ── 4. Pass all environment variables to OpenClaw ────────────────────────
#
# Export all environment variables from Balena Cloud to OpenClaw's .env file.
# This allows you to configure any provider or integration via Balena Device
# Variables, and control which ones to use in openclaw.json config.
#
OPENCLAW_ENV_FILE="/root/.openclaw/.env"
mkdir -p "$(dirname "$OPENCLAW_ENV_FILE")"

echo "Exporting all environment variables to $OPENCLAW_ENV_FILE..."
> "$OPENCLAW_ENV_FILE"

# Export all environment variables, excluding common system ones
env | while IFS='=' read -r name value; do
  # Skip if name is empty or starts with a digit (invalid var name)
  [ -z "$name" ] && continue
  [[ "$name" =~ ^[0-9] ]] && continue

  # Skip common system/internal variables that shouldn't be exported
  case "$name" in
    HOME|USER|PATH|PWD|OLDPWD|SHELL|TERM|HOSTNAME|SHLVL|_|\
    LANG|LC_*|TZ|DEBIAN_FRONTEND|NODE_VERSION|YARN_VERSION|\
    INIT_CWD|npm_config_*|npm_lifecycle_*|npm_package_*|npm_execpath|\
    BALENA_*|RESIN_*)
      continue
      ;;
  esac

  # Get the full value (env output might be truncated)
  full_value="${!name}"

  # Only export if it has actual content
  if has_value "$full_value"; then
    # Write to .env file with proper shell quoting
    printf "%s='%s'\n" "$name" "${full_value//\'/\'\\\'\'}" >> "$OPENCLAW_ENV_FILE"
    echo "  - ${name} configured"
  fi
done

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
