#!/bin/bash
set -euo pipefail
umask 077
library_dir=${1:-"$HOME/Library/Application Support/Agora"}
mkdir -p "$library_dir"
chmod 700 "$library_dir"
certificate="$library_dir/localhost.crt"
if [[ ! -f "$library_dir/localhost.p12" || ! -f "$library_dir/localhost-passphrase" ]] || ! /usr/bin/openssl x509 -checkend 2592000 -noout -in "$certificate" >/dev/null 2>&1; then
  work=$(mktemp -d "${TMPDIR:-/tmp}/agora-cert.XXXXXX")
  trap 'rm -rf "$work"' EXIT
  cat > "$work/openssl.cnf" <<'CONF'
[req]
distinguished_name = dn
x509_extensions = extensions
prompt = no
[dn]
CN = Agora Localhost
O = Agora on this Mac
[extensions]
subjectAltName = DNS:localhost,IP:127.0.0.1
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
CONF
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 365 -sha256 -config "$work/openssl.cnf" -keyout "$work/localhost.key" -out "$work/localhost.crt" 2>/dev/null
  /usr/bin/openssl rand -hex 32 > "$work/passphrase"
  /usr/bin/openssl pkcs12 -export -inkey "$work/localhost.key" -in "$work/localhost.crt" -out "$work/localhost.p12" -passout "file:$work/passphrase"
  cp "$work/localhost.crt" "$certificate"
  cp "$work/localhost.p12" "$library_dir/localhost.p12"
  cp "$work/passphrase" "$library_dir/localhost-passphrase"
fi
if [[ ${AGORA_SKIP_CERT_TRUST:-0} != 1 ]]; then
  /usr/bin/security add-trusted-cert -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" "$certificate"
fi
echo "Local HTTPS is configured. Keep Agora open while capturing Outlook emails."
