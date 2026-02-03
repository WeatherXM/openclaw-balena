# Claw-on-Balena (OpenClaw + local llama.cpp)

[![Deploy with balena](https://balena.io/deploy.svg)](https://dashboard.balena-cloud.com/deploy?repoUrl=https://github.com/WeatherXM/openclaw-balena&defaultDeviceType=raspberrypi4-64)

This project packages **OpenClaw Gateway** together with a local LLM server (based on **llama.cpp**) so you can deploy an AI agent easily on:

- Raspberry Pi 4 / 5 (64-bit)
- Jetson Nano (64-bit)

By default it runs fully local inference (no cloud keys required). You can still switch to cloud providers later by setting environment variables.

---

## What runs in this app

### Services

| Service | Description |
|---------|-------------|
| `llama` | llama.cpp HTTP server exposing an OpenAI-style `/v1` API |
| `gateway` | OpenClaw Gateway configured to use that local `/v1` endpoint as its default model provider |

### Ports (LAN only recommended)

| Port | Service |
|------|---------|
| `18789/tcp` | OpenClaw Gateway UI/API |
| `8080/tcp` | llama.cpp server (kept internal unless you choose to expose it) |

---

## Deploy on Balena

### 1) Click the Deploy Button

Click the button at the top of this README, or use this link:

👉 **[Deploy to balenaCloud](https://dashboard.balena-cloud.com/deploy?repoUrl=https://github.com/WeatherXM/openclaw-balena&defaultDeviceType=raspberrypi4-64)**

This will:
- Create a new application in your balenaCloud account
- Let you select your device type (Raspberry Pi 4/5, Jetson Nano)
- Flash and provision your device automatically

### 2) Set Device Variables (optional but recommended)

After deployment, set these in the balenaCloud dashboard under **Device Variables**:

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENCLAW_GATEWAY_TOKEN` | Recommended | Auth token for the Gateway UI (auto-generated if not set) |
| `LLAMA_MODEL_URL` | Optional | Override the default model with a different GGUF URL |

### 3) Open the Gateway UI

Browse to:

```
http://<device-ip>:18789
```

If the UI asks for a token:
- Use the `OPENCLAW_GATEWAY_TOKEN` you set in Balena
- Or check the device logs for the auto-generated token

### 4) Access llama.cpp server directly (optional)

The llama.cpp server exposes an OpenAI-compatible API on port `8080`. You can use it directly:

```
http://<device-ip>:8080
```

**Test the API:**

```bash
# List models
curl http://<device-ip>:8080/v1/models

# Chat completion
curl http://<device-ip>:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "local-gguf",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

This is useful if you want to integrate other applications with the local LLM.

---

## Run locally (for development)

If you want to test on a laptop/server first:

```bash
docker compose up --build
```

Then open: http://localhost:18789

---

## Environment Variables

Below are all configurable variables. Everything is optional unless marked.

### A) OpenClaw Gateway variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCLAW_GATEWAY_PORT` | `18789` | Gateway HTTP port |
| `OPENCLAW_GATEWAY_TOKEN` | *(auto-generated)* | Token used to access the Gateway UI/API |
| `OPENCLAW_CONFIG_PATH` | `/data/openclaw/openclaw.json` | Path to the rendered config file |
| `LOCAL_LLM_BASE_URL` | `http://llama:8080/v1` | OpenAI-compatible base URL for local LLM |
| `LOCAL_LLM_MODEL_ID` | `local-gguf` | Model ID string OpenClaw will request from the `/v1` API |

### B) llama.cpp server variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LLAMA_PORT` | `8080` | Port the server listens on |
| `LLAMA_HOST` | `0.0.0.0` | Bind address |
| `LLAMA_MODEL_URL` | *(see docker-compose)* | Model download URL (GGUF format) |
| `LLAMA_MODEL_PATH` | `/models/model.gguf` | Where the model is stored |
| `LLAMA_CTX_SIZE` | `2048` | Context size |
| `LLAMA_N_PREDICT` | `256` | Max new tokens per request |

### Changing the model

**Option 1: Direct URL**
```
LLAMA_MODEL_URL=https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf
```

**Option 2: Different quantization**
```
LLAMA_MODEL_URL=https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q8_0.gguf
```

---

## Switching to a cloud model (optional)

You can keep the local LLM running but configure OpenClaw to use a cloud provider instead.

1. Set `OPENCLAW_DEFAULT_MODEL_REF=openai/gpt-4o-mini` (or another provider/model)
2. Set `OPENAI_API_KEY` (or the appropriate provider key)

OpenClaw supports multiple providers and OpenAI-compatible endpoints. See the [OpenClaw documentation](https://github.com/clawdbot/openclaw) for configuration examples.

---

## Security recommendations

- Run your bot isolated (dedicated device / separate network segment)
- Avoid granting high-privilege skills unless you've audited them
- Consider setting `OPENCLAW_GATEWAY_TOKEN` explicitly rather than using auto-generated tokens

---

## License

MIT
