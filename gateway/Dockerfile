FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    tini \
    gettext-base \
    git \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g openclaw

WORKDIR /app

COPY start.sh /app/start.sh
COPY config/openclaw.json /app/openclaw.json.template

RUN chmod +x /app/start.sh

EXPOSE 18789
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/app/start.sh"]
