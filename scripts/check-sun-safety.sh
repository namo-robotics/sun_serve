#!/usr/bin/env bash
# Reject unsafe Sun code outside the audited low-level boundary.
set -euo pipefail
cd "$(dirname "$0")/.."

shopt -s globstar nullglob
sun_files=(src/**/*.sun cmd/**/*.sun tests/**/*.sun examples/**/*.sun)

status=0
while IFS=: read -r file line source; do
  case "$file" in
    src/sys_ffi.sun|src/abi_linux.sun|src/buffer.sun|src/net.sun|src/epoll.sun|src/websocket.sun|src/transport.sun|src/signals.sun|src/tls/*.sun)
      ;;
    cmd/sun_serve/main.sun)
      if [[ "$source" != *"argv: raw_ptr<raw_ptr<i8>>"* ]]; then
        echo "$file:$line: raw pointers are only allowed in the process entrypoint signature" >&2
        status=1
      fi
      ;;
    *)
      echo "$file:$line: unsafe code must stay inside an approved low-level boundary" >&2
      status=1
      ;;
  esac
done < <(grep -EnH '(^|[^[:alnum:]_])unsafe([^[:alnum:]_]|$)|raw_ptr<' "${sun_files[@]}" || true)

while IFS=: read -r file line source; do
  if [[ "$file" != "cmd/sun_serve/main.sun" ]]; then
    echo "$file:$line: public APIs must not expose raw pointers" >&2
    status=1
  fi
done < <(grep -EnH '^[[:space:]]*public .*raw_ptr<' "${sun_files[@]}" || true)

exit "$status"
