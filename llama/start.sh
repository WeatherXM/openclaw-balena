#!/usr/bin/env bash
set -euo pipefail

: "${LLAMA_PORT:=8080}"
: "${LLAMA_HOST:=0.0.0.0}"
: "${LLAMA_MODEL_PATH:=/models/model.gguf}"
: "${LLAMA_N_PREDICT:=256}"
: "${LLAMA_CTX_SIZE:=2048}"

mkdir -p "$(dirname "$LLAMA_MODEL_PATH")"

if [ ! -f "$LLAMA_MODEL_PATH" ]; then
  if [ -z "${LLAMA_MODEL_URL:-}" ]; then
    echo "ERROR: No model found at $LLAMA_MODEL_PATH and LLAMA_MODEL_URL is empty."
    exit 1
  fi
  echo "Downloading model to $LLAMA_MODEL_PATH ..."
  curl -L --retry 5 --retry-delay 2 -o "$LLAMA_MODEL_PATH" "$LLAMA_MODEL_URL"
fi

echo "Starting llama-server..."
exec /app/llama-server \
  -m "$LLAMA_MODEL_PATH" \
  --host "$LLAMA_HOST" \
  --port "$LLAMA_PORT" \
  -n "$LLAMA_N_PREDICT" \
  --ctx-size "$LLAMA_CTX_SIZE"
