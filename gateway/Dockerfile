FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    tini \
    gettext-base \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g openclaw

# node user already exists in node:22-bookworm-slim base image
USER node
WORKDIR /home/node

COPY --chown=node:node start.sh /home/node/start.sh
COPY --chown=node:node config/openclaw.json /home/node/openclaw.json.template

RUN chmod +x /home/node/start.sh

EXPOSE 18789
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/home/node/start.sh"]
