FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    tini \
    gettext-base \
    git \
    python3 \
    python3-pip \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g openclaw

WORKDIR /app

COPY start.sh /app/start.sh
COPY config/openclaw.json5.template /app/openclaw.json5.template

RUN chmod +x /app/start.sh

EXPOSE 80
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/app/start.sh"]
