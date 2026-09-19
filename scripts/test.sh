#!/usr/bin/env bash
# Run every test suite. Pass --jit to run under the JIT instead of the
# compiled test binaries (slower to start, no build step needed). The compiled
# run builds first, which only recompiles what changed, so the suites never
# run against stale binaries.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--jit" ]]; then
  sun test sun-config.json
  exit 0
fi
scripts/build.sh
build/sun_serve_lib_test
build/sun_serve_test
build/hello_handler_test
scripts/test-nghttp.sh
