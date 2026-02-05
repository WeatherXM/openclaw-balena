# OpenClaw on Balena

[![Deploy with balena](https://balena.io/deploy.svg)](https://dashboard.balena-cloud.com/deploy?repoUrl=https://github.com/WeatherXM/openclaw-balena&defaultDeviceType=raspberrypi4-64)

This project packages **OpenClaw Gateway** for easy deployment on:

- Raspberry Pi 4 / 5 (64-bit)
- Jetson Nano (64-bit)

Connect to cloud AI providers (Google Gemini, OpenAI, Anthropic, OpenRouter) by setting your API keys.

---

## What runs in this app

### Services

| Service | Description |
|---------|-------------|
| `gateway` | OpenClaw Gateway - your personal AI assistant control plane |

### Ports

| Port | Service |
|------|---------|
| `80/tcp` | OpenClaw Gateway UI/API |

---

## Deploy on Balena

### 1) Click the Deploy Button

Click the button at the top of this README, or use this link:

👉 **[Deploy to balenaCloud](https://dashboard.balena-cloud.com/deploy?repoUrl=https://github.com/WeatherXM/openclaw-balena&defaultDeviceType=raspberrypi4-64)**

This will:
- Create a new application in your balenaCloud account
- Let you select your device type (Raspberry Pi 4/5, Jetson Nano)
- Flash and provision your device automatically

### 2) Set Device Variables (required)

After deployment, set these in the balenaCloud dashboard under **Device Variables**:

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENCLAW_GATEWAY_TOKEN` | Recommended | Auth token for the Gateway UI (auto-generated if not set) |
| `GOOGLE_API_KEY` | One of these | API key for Google Gemini |
| `OPENAI_API_KEY` | One of these | API key for OpenAI |
| `ANTHROPIC_API_KEY` | One of these | API key for Anthropic |
| `OPENROUTER_API_KEY` | One of these | API key for OpenRouter |

### 3) Open the Gateway UI

Browse to:

```
http://<device-ip>
```

If the UI asks for a token:
- Use the `OPENCLAW_GATEWAY_TOKEN` you set in Balena
- Or check the device logs for the auto-generated token

---

## Run locally (for development)

If you want to test on a laptop/server first:

```bash
# Set your API key
export GOOGLE_API_KEY=AIza...
# Or: export OPENAI_API_KEY=sk-...
# Or: export ANTHROPIC_API_KEY=sk-ant-...
# Or: export OPENROUTER_API_KEY=sk-or-...

docker compose up --build
```

Then open: http://localhost

---

## Environment Variables

### OpenClaw Gateway variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCLAW_GATEWAY_PORT` | `80` | Gateway HTTP port |
| `OPENCLAW_GATEWAY_TOKEN` | *(auto-generated)* | Token used to access the Gateway UI/API |
| `OPENCLAW_CONFIG_PATH` | `/data/openclaw/openclaw.json` | Path to the rendered config file |

### Model Provider API Keys

Set one of the following depending on your preferred provider:

| Variable | Description |
|----------|-------------|
| `GOOGLE_API_KEY` | API key for Google Gemini models (gemini-flash, gemini-pro, etc.) |
| `OPENAI_API_KEY` | API key for OpenAI models (gpt-4o, gpt-4o-mini, etc.) |
| `ANTHROPIC_API_KEY` | API key for Anthropic models (claude-sonnet-4-20250514, claude-3-haiku, etc.) |
| `OPENROUTER_API_KEY` | API key for OpenRouter (access to many models) |

---

## Supported Providers

OpenClaw supports multiple AI providers out of the box:

- **Google** - Gemini Flash, Gemini Pro, etc.
- **OpenAI** - GPT-4o, GPT-4o-mini, etc.
- **Anthropic** - Claude Sonnet, Claude Haiku, etc.
- **OpenRouter** - Access to 100+ models from various providers
- **And more** - See [OpenClaw documentation](https://docs.openclaw.ai) for full list

---

## Security recommendations

- Run your bot isolated (dedicated device / separate network segment)
- Avoid granting high-privilege skills unless you've audited them
- Consider setting `OPENCLAW_GATEWAY_TOKEN` explicitly rather than using auto-generated tokens
- Keep your API keys secure - use balenaCloud Device Variables

---

## License

MIT
