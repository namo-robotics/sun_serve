#!/usr/bin/env bash
# Run every test suite. Pass --jit to run under the JIT instead of the
# compiled test binaries (slower to start, no build step needed).
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--jit" ]]; then
  sun test src/sun_serve.sun
  sun test cmd/sun_serve/main.sun
  sun test examples/hello_handler/main.sun
  exit 0
fi
[[ -x build/sun_serve_lib_test ]] || scripts/build.sh
build/sun_serve_lib_test
build/sun_serve_test
build/hello_handler_test
