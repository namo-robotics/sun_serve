#!/usr/bin/env bash
# Check cleartext HTTP/2 interoperability with the nghttp reference client.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v nghttp >/dev/null 2>&1; then
  echo "SKIP nghttp interoperability check: nghttp is not installed"
  exit 0
fi

port="${SUN_SERVE_NGHTTP_PORT:-18082}"
client_log="$(mktemp)"
server_log="$(mktemp)"
server_pid=""
cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill -TERM "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -f "$client_log" "$server_log"
}
trap cleanup EXIT

build/sun_serve --root . --listen "127.0.0.1:${port}" --workers 1 \
  --no-access-log --log-level error >"$server_log" 2>&1 &
server_pid="$!"

ok=0
for _ in $(seq 1 20); do
  if nghttp -nv "http://127.0.0.1:${port}/README.md" >"$client_log" 2>&1; then
    ok=1
    break
  fi
  sleep 0.1
done
if [[ "$ok" -ne 1 ]] || ! grep -q ':status: 200' "$client_log"; then
  cat "$client_log" >&2
  cat "$server_log" >&2
  echo "nghttp interoperability check failed" >&2
  exit 1
fi

echo "PASS nghttp HTTP/2 interoperability"
