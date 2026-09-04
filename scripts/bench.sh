#!/usr/bin/env bash
# Serve a scratch directory and measure requests per second over HTTP and
# HTTPS with whichever load generator is installed (oha, wrk, hey, ab), or
# a curl loop as a last resort. Finishes by checking that SIGTERM exits 0.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -x build/sun_serve ]] || scripts/build.sh
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
head -c 1024 /dev/urandom | base64 > "$root/small.txt"
head -c 1048576 /dev/urandom | base64 > "$root/large.txt"
echo "<h1>bench</h1>" > "$root/index.html"
scripts/mkcert.sh "$root" > /dev/null
build/sun_serve --root "$root" --listen 127.0.0.1:18080 --tls-listen 127.0.0.1:18443 \
  --cert "$root/cert.pem" --key "$root/key.pem" --no-access-log --log-level warn &
pid=$!
sleep 0.5
run() {
  local url="$1"
  if command -v oha > /dev/null; then oha -z 5s -c 64 --no-tls-verify "$url" | grep -E "Requests/sec|Success rate"
  elif command -v wrk > /dev/null; then wrk -t4 -c64 -d5s "$url" | grep -E "Requests/sec"
  elif command -v hey > /dev/null; then hey -z 5s -c 64 "$url" | grep -E "Requests/sec"
  elif command -v ab > /dev/null; then ab -k -t 5 -c 64 -q "$url" | grep -E "Requests per second"
  else
    local start end n
    start=$(date +%s.%N); n=2000
    seq "$n" | xargs -P 64 -I{} curl -sk -o /dev/null "$url"
    end=$(date +%s.%N)
    awk -v n="$n" -v s="$start" -v e="$end" 'BEGIN { printf "curl loop (one connection per request): %.0f requests/sec\n", n / (e - s) }'
  fi
}
for path in /small.txt /large.txt; do
  echo "== http $path"; run "http://127.0.0.1:18080$path"
  echo "== https $path"; run "https://127.0.0.1:18443$path"
done
kill -TERM "$pid"
wait "$pid" && echo "clean shutdown: exit 0"
