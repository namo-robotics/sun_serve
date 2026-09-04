#!/usr/bin/env bash
# Mint a self-signed certificate for local development.
# Usage: scripts/mkcert.sh [OUT_DIR] [HOSTNAME]
set -euo pipefail
out="${1:-build}"
host="${2:-localhost}"
mkdir -p "$out"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
  -days 365 -subj "/CN=$host" -addext "subjectAltName=DNS:$host" \
  -keyout "$out/key.pem" -out "$out/cert.pem" 2>/dev/null
echo "wrote $out/cert.pem and $out/key.pem for $host"
