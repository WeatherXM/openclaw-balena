#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# OpenClaw Balena – start script
# ---------------------------------------------------------------------------
# 1. Runtime version management (self-contained snapshots with auto-prune)
# 2. Token management            (OPENCLAW_GATEWAY_TOKEN)
# 3. Config rendering             (JSON5 template → openclaw.json)
# 4. API-key injection            (provider keys → ~/.openclaw/.env)
# 5. Skills installation          (OPENCLAW_SKILLS env var)
# 6. Plugins installation         (OPENCLAW_PLUGINS env var)
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
STATE_DIR="/data/openclaw"
mkdir -p "$STATE_DIR"

VERSIONS_DIR="$STATE_DIR/versions"
CURRENT_VERSION_FILE="$STATE_DIR/.current-version"
KEEP_VERSIONS="${OPENCLAW_KEEP_VERSIONS:-3}"
mkdir -p "$VERSIONS_DIR"

# ── 1. Runtime OpenClaw version management ────────────────────────────────
#
# Each version is a fully self-contained snapshot:
#   versions/X/npm-global/      – openclaw binary + node_modules
#   versions/X/openclaw.json    – gateway config
#   versions/X/openclaw-home/   – .openclaw/ data (skills, plugins, memory)
#
# On upgrade: clone previous snapshot (config + home), install new binary.
# On rollback: switch to existing snapshot (everything untouched).
# Auto-prune: keep last N versions (OPENCLAW_KEEP_VERSIONS, default 3).
#

# Get the currently active version
CURRENT_VERSION="unknown"
if [ -f "$CURRENT_VERSION_FILE" ]; then
  CURRENT_VERSION="$(cat "$CURRENT_VERSION_FILE")"
fi

# Get desired version from env var
DESIRED_VERSION="$(clean_var "${OPENCLAW_VERSION:-}")"
DESIRED_VERSION="${DESIRED_VERSION#v}"

# If no version set, use the one baked in the image
if [ -z "$DESIRED_VERSION" ]; then
  RAW_VERSION="$(openclaw --version 2>/dev/null | head -1 || echo "unknown")"
  DESIRED_VERSION="$(extract_version "$RAW_VERSION")"
  DESIRED_VERSION="${DESIRED_VERSION:-unknown}"
  echo "OpenClaw version: ${DESIRED_VERSION} (from image, no OPENCLAW_VERSION override set)"
fi

VERSION_DIR="$VERSIONS_DIR/$DESIRED_VERSION"
PREVIOUS_VERSION_DIR="$VERSIONS_DIR/$CURRENT_VERSION"

if [ "$CURRENT_VERSION" != "$DESIRED_VERSION" ]; then
  echo "╔═══════════════════════════════════════════════════════════════╗"
  echo "║  OpenClaw version change detected                           ║"
  echo "║  Current : ${CURRENT_VERSION}"
  echo "║  Target  : ${DESIRED_VERSION}"
  echo "╚═══════════════════════════════════════════════════════════════╝"

  if [ -d "$VERSION_DIR" ]; then
    # Version directory exists — rollback, use snapshot as-is
    echo "Version ${DESIRED_VERSION} already installed (rollback, using existing snapshot)"
  else
    # New version — clone snapshot from previous version, then install new binary
    mkdir -p "$VERSION_DIR"

    if [ -d "$PREVIOUS_VERSION_DIR" ]; then
      echo "Cloning snapshot from ${CURRENT_VERSION} to ${DESIRED_VERSION}..."
      # Clone everything except npm-global (will be freshly installed)
      for item in "$PREVIOUS_VERSION_DIR"/*; do
        [ ! -e "$item" ] && continue
        basename_item="$(basename "$item")"
        [ "$basename_item" = "npm-global" ] && continue
        if cp -a "$item" "$VERSION_DIR/"; then
          echo "  cloned: ${basename_item}"
        fi
      done
      echo "✓ Snapshot cloned"
    else
      echo "No previous version to clone from (fresh install)"
    fi

    # Install the new version binary
    echo "Installing openclaw@${DESIRED_VERSION}..."
    INSTALL_PREFIX="$VERSION_DIR/npm-global"
    mkdir -p "$INSTALL_PREFIX"

    if npm install -g --prefix "$INSTALL_PREFIX" --loglevel verbose "openclaw@${DESIRED_VERSION}"; then
      NEW_VERSION="$(extract_version "$(PATH="$INSTALL_PREFIX/bin:$PATH" openclaw --version 2>/dev/null | head -1)")"
      echo "✓ OpenClaw ${NEW_VERSION:-unknown} installed"
    else
      echo "⚠ Failed to install openclaw@${DESIRED_VERSION} – falling back to previous version"
      rm -rf "$VERSION_DIR"
      VERSION_DIR="$PREVIOUS_VERSION_DIR"
      DESIRED_VERSION="$CURRENT_VERSION"
    fi
  fi

  # Record current version and touch dir for mtime-based pruning
  echo -n "$DESIRED_VERSION" > "$CURRENT_VERSION_FILE"
  touch "$VERSION_DIR" 2>/dev/null || true

  # Auto-prune old versions (keep last N by modification time)
  if [ "$KEEP_VERSIONS" -gt 0 ] 2>/dev/null; then
    VERSION_COUNT=$(find "$VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
    if [ "$VERSION_COUNT" -gt "$KEEP_VERSIONS" ]; then
      echo "Pruning old versions (keeping last ${KEEP_VERSIONS})..."
      find "$VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' \
        | sort -rn \
        | tail -n +"$((KEEP_VERSIONS + 1))" \
        | cut -d' ' -f2- \
        | while read -r old_dir; do
            old_ver="$(basename "$old_dir")"
            # Never prune the current version
            if [ "$old_ver" != "$DESIRED_VERSION" ]; then
              echo "  pruning: ${old_ver}"
              rm -rf "$old_dir"
            fi
          done
    fi
  fi
else
  echo "OpenClaw ${CURRENT_VERSION} already at requested version."
fi

# ── List installed version snapshots ─────────────────────────────────────
if [ -d "$VERSIONS_DIR" ]; then
  INSTALLED=$(ls -1 "$VERSIONS_DIR" 2>/dev/null)
  if [ -n "$INSTALLED" ]; then
    echo "──────────────────────────────────────────────────────────────────"
    echo "  Installed versions:"
    echo "$INSTALLED" | while read -r ver; do
      if [ "$ver" = "$DESIRED_VERSION" ]; then
        echo "    $ver  ← active"
      else
        echo "    $ver"
      fi
    done
    echo "──────────────────────────────────────────────────────────────────"
  fi
fi

# ── Activate version snapshot ─────────────────────────────────────────────

# Set PATH to use this version's binary
NPM_PERSIST_DIR="$VERSION_DIR/npm-global"
mkdir -p "$NPM_PERSIST_DIR"
export PATH="${NPM_PERSIST_DIR}/bin:${PATH}"

# Version-specific home directory (~/.openclaw data)
VERSION_HOME="$VERSION_DIR/openclaw-home"
mkdir -p "$VERSION_HOME"

# Version-specific config
export OPENCLAW_CONFIG_PATH="$VERSION_DIR/openclaw.json"

# Migrate from shared layout to per-version layout (one-time)
# If ~/.openclaw is a real directory (not our symlink), move its contents
if [ -d "/root/.openclaw" ] && [ ! -L "/root/.openclaw" ]; then
  echo "Migrating shared .openclaw to version snapshot..."
  cp -a /root/.openclaw/* "$VERSION_HOME/" 2>/dev/null || true
  rm -rf /root/.openclaw
  echo "✓ Migrated .openclaw data"
fi
# Migrate shared config if present and version doesn't have one yet
LEGACY_CONFIG="$STATE_DIR/openclaw.json"
if [ -f "$LEGACY_CONFIG" ] && [ ! -f "$OPENCLAW_CONFIG_PATH" ]; then
  cp -a "$LEGACY_CONFIG" "$OPENCLAW_CONFIG_PATH"
  echo "✓ Migrated config to version snapshot"
fi

# Point ~/.openclaw at the active version's home
ln -sfn "$VERSION_HOME" /root/.openclaw

echo "Active snapshot: $VERSION_DIR"

# ── 2. Ensure gateway token exists ────────────────────────────────────────
# Token is shared across versions (changing version shouldn't break auth)
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

# Patch existing configs: add controlUi.allowedOrigins if missing
# (required by newer OpenClaw versions when behind a reverse proxy)
if [ -f "$OPENCLAW_CONFIG_PATH" ] && ! grep -q 'allowedOrigins' "$OPENCLAW_CONFIG_PATH"; then
  ORIGIN_URL="http://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-8080}"
  echo "Patching config: adding controlUi.allowedOrigins [\"${ORIGIN_URL}\"]..."
  sed -i "s|\(auth: {[^}]*}\)|\1,\n    controlUi: { allowedOrigins: [\"${ORIGIN_URL}\"] }|" "$OPENCLAW_CONFIG_PATH"
  echo "✓ Patched config with controlUi.allowedOrigins"
fi

# Patch: add balena public URL to allowedOrigins so the gateway accepts
# requests arriving via the balena public URL (BALENA_DEVICE_UUID is set
# automatically by the balena supervisor in every container).
BALENA_UUID="$(clean_var "${BALENA_DEVICE_UUID:-}")"
if [ -n "$BALENA_UUID" ] && [ -f "$OPENCLAW_CONFIG_PATH" ]; then
  if grep -q 'allowedOrigins' "$OPENCLAW_CONFIG_PATH" && ! grep -q "$BALENA_UUID" "$OPENCLAW_CONFIG_PATH"; then
    BALENA_ORIGIN="https://${BALENA_UUID}.balena-devices.com"
    echo "Patching config: adding balena public URL to allowedOrigins..."
    sed -i "s|allowedOrigins: \[|allowedOrigins: [\"${BALENA_ORIGIN}\", |" "$OPENCLAW_CONFIG_PATH"
    echo "✓ Added ${BALENA_ORIGIN} to allowedOrigins"
  fi
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
# Skills are installed to ~/.openclaw/skills/ (version-specific snapshot).
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
# Plugins are installed to ~/.openclaw/extensions/ (version-specific snapshot).
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

# ── 6.5. Auto-fix configuration issues (optional) ────────────────────────
#
# If OPENCLAW_AUTO_DOCTOR is set, automatically run openclaw doctor --fix
# to repair common configuration issues before starting the gateway.
#
if [ "${OPENCLAW_AUTO_DOCTOR:-false}" = "true" ]; then
  echo "──────────────────────────────────────────────────────────────────"
  echo "  Running openclaw doctor --fix"
  echo "──────────────────────────────────────────────────────────────────"
  if openclaw doctor --fix 2>&1; then
    echo "  ✓ Configuration issues fixed"
  else
    echo "  ⚠ Doctor encountered issues (continuing with current config)"
  fi
fi

# ── 7. Launch the gateway ─────────────────────────────────────────────────
if [ "${OPENCLAW_GATEWAY_STOP:-false}" = "true" ]; then
  echo ""
  echo "⚠ OPENCLAW_GATEWAY_STOP is set – gateway startup skipped"
  echo "Container will remain running for manual intervention (e.g., openclaw doctor)."
  echo ""
  # Keep container alive for manual commands
  exec tail -f /dev/null
else
  echo ""
  echo "Starting OpenClaw gateway..."
  exec openclaw gateway
fi
