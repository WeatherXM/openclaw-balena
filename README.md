# OpenClaw on Balena

[![Deploy with balena](https://balena.io/deploy.svg)](https://dashboard.balena-cloud.com/deploy?repoUrl=https://github.com/WeatherXM/openclaw-balena&defaultDeviceType=raspberrypi4-64)

Run [OpenClaw](https://github.com/openclaw/openclaw) on a Raspberry Pi as a self-hosted AI assistant. OpenClaw is an open-source personal AI gateway that connects to cloud providers (Google Gemini, OpenAI, Anthropic, OpenRouter) and exposes a web UI, multi-channel messaging inbox, voice interaction, browser automation, and a skills/plugin ecosystem — all running on your own hardware.

This project wraps the OpenClaw Gateway in a Balena container so you can deploy and manage it via the balenaCloud dashboard with OTA updates.

**Supported devices:** Raspberry Pi 4, Raspberry Pi 5

---

## Setup

### 1. Deploy to balenaCloud

Click the deploy button above, or use this link:

**[Deploy to balenaCloud](https://dashboard.balena-cloud.com/deploy?repoUrl=https://github.com/WeatherXM/openclaw-balena&defaultDeviceType=raspberrypi4-64)**

This creates a new application in your balenaCloud account and lets you flash your device.

### 2. Configure environment variables

**All environment variables** you set in balenaCloud Device Variables are automatically passed to OpenClaw and available in its runtime environment.

In the balenaCloud dashboard, go to **Device Variables** and set at least one AI provider key:

| Variable | Provider |
|----------|----------|
| `GOOGLE_API_KEY` | Google Gemini |
| `OPENAI_API_KEY` | OpenAI |
| `ANTHROPIC_API_KEY` | Anthropic |
| `OPENROUTER_API_KEY` | OpenRouter (100+ models) |

You only need one. Set whichever provider you have an account with.

**Any other environment variable** you add in Balena Cloud will be automatically exported to OpenClaw's environment (`~/.openclaw/.env`), allowing you to configure integrations, custom providers, or any other settings. You can then reference these in your `openclaw.json` config to control which ones OpenClaw actually uses.

### 3. Open the UI

Browse to `https://<device-ip>` (port 443). Your browser will show a certificate warning for the self-signed TLS certificate — accept it once. If prompted for a token, check the device logs in the Balena dashboard — one is auto-generated on first boot.

To set your own token, add a `OPENCLAW_GATEWAY_TOKEN` device variable.

---

## Environment Variables

**All environment variables** set in Balena Cloud Device Variables are automatically exported to OpenClaw and written to `~/.openclaw/.env`. This allows you to:

- Configure any AI provider (official or custom)
- Set integration credentials (Home Assistant, MQTT, etc.)
- Pass custom configuration values to skills and plugins
- Control feature flags and runtime behavior

The start script filters out common system variables (PATH, HOME, etc.) but passes everything else through. You can then reference these variables in your [openclaw.json config](gateway/config/openclaw.json5.template) to control which providers and integrations OpenClaw uses.

**Example workflow:**

1. Add a Device Variable in Balena Cloud: `CUSTOM_API_KEY=sk-xyz123`
2. The variable is automatically written to `~/.openclaw/.env`
3. Reference it in your openclaw.json config file
4. OpenClaw can now use this key at runtime

This design gives you full control — set any variables you need in Balena Cloud, then configure openclaw.json to use only the ones you want.

### Common Runtime Flags

| Variable | Value | Purpose |
|----------|-------|---------|
| `OPENCLAW_VERSION` | e.g., `2026.2.19` | Install a specific OpenClaw version at boot (see [releases](https://github.com/openclaw/openclaw/releases)) |
| `OPENCLAW_AUTO_DOCTOR` | `true` | Automatically run `openclaw doctor --fix` before starting to repair configuration issues |
| `OPENCLAW_GATEWAY_STOP` | `true` | Skip gateway startup; keeps container running for manual intervention (e.g., `openclaw doctor`) |
| `OPENCLAW_GATEWAY_TOKEN` | custom token | Set a custom authentication token instead of auto-generating |
| `OPENCLAW_SKILLS` | `skill1,skill2` | Auto-install ClawHub skills at boot |
| `OPENCLAW_PLUGINS` | `plugin1,plugin2` | Auto-install plugins at boot |
| `OPENCLAW_KEEP_VERSIONS` | e.g., `3` | Number of version snapshots to keep for rollback (default: 3) |
| `HAPROXY_CERT_CN` | e.g., `openclaw.local` | Common Name for the self-signed TLS certificate (default: `openclaw.local`) |

### Troubleshooting: Config Issues

If OpenClaw fails to start due to a corrupted `openclaw.json` configuration, you have two options:

**Option 1: Auto-fix (recommended)**
1. Set `OPENCLAW_AUTO_DOCTOR=true` in Device Variables
2. Restart the container
3. The container will automatically run `openclaw doctor --fix` before starting the gateway and repair any config issues
4. Once fixed, remove `OPENCLAW_AUTO_DOCTOR` and restart to prevent unnecessary doctor runs on subsequent boots

**Option 2: Manual fix**
1. Set `OPENCLAW_GATEWAY_STOP=true` in Device Variables
2. Restart the container (do not update the service)
3. Once the container is running, open a terminal and run:
   ```bash
   docker exec <container-id> openclaw doctor
   ```
4. Follow the interactive prompts to repair your configuration
5. Remove `OPENCLAW_GATEWAY_STOP` and restart to resume normal operation

---

## Updating OpenClaw

You can update OpenClaw without rebuilding the image. Set the `OPENCLAW_VERSION` device variable to a specific release (e.g. `2026.2.19`) and restart the service. The container will install the requested version at boot and keep it in persistent storage.

Leave `OPENCLAW_VERSION` unset to keep the version that was baked in at the last image build.

**Finding the latest version:**

Check [OpenClaw releases on GitHub](https://github.com/openclaw/openclaw/releases) for the latest stable version, or check your device logs to see which version is currently running (printed on startup).

### Versioned Snapshots & Rollback

Each version is a **fully self-contained snapshot** under `/data/openclaw/versions/{version}/`, including config, skills, plugins, memory, and the openclaw binary. This means rolling back to a previous version restores everything exactly as it was — no risk of config incompatibility.

**When upgrading to a new version:**
1. Config, skills, plugins, and memory are cloned from the previous version's snapshot
2. A fresh openclaw binary is installed into the new snapshot
3. If the upgrade fails, the previous version is used automatically

**When rolling back:**
1. Change `OPENCLAW_VERSION` back to the desired version (e.g., `2026.2.12`)
2. The previous snapshot is activated as-is — config, skills, and memory are exactly as they were

**Auto-pruning:**
Old version snapshots are automatically pruned to save disk space. Set `OPENCLAW_KEEP_VERSIONS` to control how many are kept (default: 3). The current version is never pruned.

```bash
# List installed version snapshots
ls /data/openclaw/versions/

# Manually remove a specific old version
rm -rf /data/openclaw/versions/2026.2.10
```

### Persistent Storage

Two volumes persist across container updates and restarts:

| Volume | Mount | Contents |
|--------|-------|----------|
| `openclaw_data` | `/data` | OpenClaw versions, config, state, and npm-installed binaries |
| `openclaw_home` | `/root` | User home including skills, plugins, sessions, and application configs |
| `proxy_certs` | `/etc/haproxy/certs` | Self-signed TLS certificate (persists across restarts) |

**Storage structure:**
```
/data/openclaw/
├── versions/
│   ├── 2026.2.19/
│   │   ├── npm-global/          # openclaw binary + node_modules
│   │   ├── openclaw.json        # version-specific config
│   │   └── openclaw-home/       # .openclaw/ snapshot (skills, plugins, memory)
│   └── 2026.2.18/
│       └── ...
├── gateway.token                 # shared auth token
└── .current-version              # tracks active version
```

`~/.openclaw` is symlinked to the active version's `openclaw-home/` directory, so all openclaw commands operate within the current snapshot.

All data is preserved when updating OpenClaw version or restarting the container.

---

## Skills & Plugins

OpenClaw supports two extension mechanisms. Both persist across reboots in the device volume.

### Skills

[Skills](https://docs.openclaw.ai/tools/skills) are knowledge packages (`SKILL.md` files) that teach the AI how to use tools and services. Install them at boot by setting:

```
OPENCLAW_SKILLS=home-assistant,web-search
```

### Plugins

[Plugins](https://docs.openclaw.ai/plugin) are code modules that add new integrations (messaging channels, tools, AI providers). Install them at boot by setting:

```
OPENCLAW_PLUGINS=@openclaw/voice-call
```

You can also install skills and plugins through the OpenClaw Gateway UI at any time — they persist in the device volume and don't need to be listed in the env vars.

---

## Local development

```bash
export GOOGLE_API_KEY=AIza...   # or any other provider key
docker compose up --build
```

Then open https://localhost (accept the self-signed certificate warning)

---

## Security

- All traffic is served over HTTPS via an HAProxy reverse proxy with a self-signed certificate. HTTP on port 80 redirects to HTTPS automatically
- To replace the self-signed certificate with your own, place a PEM file (key + cert concatenated) at `/etc/haproxy/certs/self-signed.pem` on the `proxy_certs` volume
- Set `OPENCLAW_GATEWAY_TOKEN` explicitly rather than relying on auto-generation
- Keep API keys in balenaCloud Device Variables, not in code
- Audit skills before granting them elevated privileges
- Consider running the device on an isolated network segment

---

## License

MIT
