FROM node:22-bookworm-slim

ARG OPENCLAW_VERSION=latest

RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  tini \
  gettext-base \
  git \
  python3 \
  python3-dev \
  build-essential \
  pkg-config \
  libopus-dev \
  python3-pip \
  jq \
  && rm -rf /var/lib/apt/lists/*

# Upgrade npm to latest to ensure native builds use current npm/node-gyp tooling
RUN npm install -g npm@latest

# Install OpenClaw (pinned version or latest)
RUN if [ "$OPENCLAW_VERSION" = "latest" ]; then \
  npm install -g openclaw; \
  else \
  npm install -g "openclaw@${OPENCLAW_VERSION}"; \
  fi

# Ensure runtime-installed (persistent) npm global bin appears first
# so interactive shells and `docker exec` pick up the in-place upgrade.
ENV PATH=/data/openclaw/npm-global/bin:$PATH

WORKDIR /app

# Record the version baked into the image for runtime comparison
RUN openclaw --version 2>/dev/null | head -1 > /app/.openclaw-image-version || echo "unknown" > /app/.openclaw-image-version

COPY start.sh /app/start.sh
COPY config/openclaw.json5.template /app/openclaw.json5.template

RUN chmod +x /app/start.sh

EXPOSE 80
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/app/start.sh"]
