FROM haproxy:2.9-alpine

USER root
RUN apk add --no-cache openssl

RUN mkdir -p /etc/haproxy/certs

COPY entrypoint.sh /entrypoint.sh
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg

RUN chmod +x /entrypoint.sh

EXPOSE 80 443

ENTRYPOINT ["/entrypoint.sh"]
