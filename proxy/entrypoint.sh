#!/bin/sh
set -e

CERT_DIR="/etc/haproxy/certs"
CERT_FILE="${CERT_DIR}/self-signed.pem"

mkdir -p "${CERT_DIR}"

if [ ! -f "${CERT_FILE}" ]; then
  echo "Generating self-signed TLS certificate..."

  # Balena may pass unresolved placeholders like "${VAR:-}" as literal strings.
  # Strip those and fall back to default.
  CERT_CN="${HAPROXY_CERT_CN:-}"
  case "$CERT_CN" in
    *'${'*) CERT_CN="" ;;
  esac
  CERT_CN="${CERT_CN:-openclaw.local}"

  echo "Certificate CN: ${CERT_CN}"

  # Use a config file for portability (Alpine openssl may not support -addext)
  cat > /tmp/openssl.cnf <<SSLEOF
[req]
default_bits = 2048
prompt = no
distinguished_name = dn
x509_extensions = v3_ext

[dn]
CN = $CERT_CN

[v3_ext]
subjectAltName = DNS:$CERT_CN,DNS:localhost,IP:127.0.0.1
SSLEOF

  openssl req -x509 -newkey rsa:2048 \
    -keyout /tmp/key.pem \
    -out /tmp/cert.pem \
    -days 3650 \
    -nodes \
    -config /tmp/openssl.cnf

  # HAProxy expects key + cert concatenated into a single PEM file
  cat /tmp/key.pem /tmp/cert.pem > "${CERT_FILE}"
  rm -f /tmp/key.pem /tmp/cert.pem /tmp/openssl.cnf
  chmod 600 "${CERT_FILE}"

  echo "TLS certificate generated: ${CERT_FILE}"
else
  echo "Using existing TLS certificate: ${CERT_FILE}"
fi

echo "Starting HAProxy..."
exec haproxy -f /usr/local/etc/haproxy/haproxy.cfg
