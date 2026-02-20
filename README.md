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

Browse to `http://<device-ip>` (port 80). If prompted for a token, check the device logs in the Balena dashboard — one is auto-generated on first boot.

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

---

## Updating OpenClaw

You can update OpenClaw without rebuilding the image. Set the `OPENCLAW_VERSION` device variable to a specific release (e.g. `2026.2.19`) and restart the service. The container will install the requested version at boot.

Leave `OPENCLAW_VERSION` empty to keep the version that was baked in at build time.

Available versions: [OpenClaw releases](https://github.com/openclaw/openclaw/releases)

### Persistent Storage

The following directories persist across container updates and restarts:
- `/data/openclaw/` - OpenClaw state and configuration
- `/root/.openclaw/` - Skills, plugins, sessions, and agent data
- `/root/.config/` - Application configs (moltbook credentials, etc.)

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

Then open http://localhost

---

## Security

- Set `OPENCLAW_GATEWAY_TOKEN` explicitly rather than relying on auto-generation
- Keep API keys in balenaCloud Device Variables, not in code
- Audit skills before granting them elevated privileges
- Consider running the device on an isolated network segment

---

## License

MIT
