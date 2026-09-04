#!/usr/bin/env bash
# Build the library, the command, and their test binaries into build/.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
scripts/check-sun-safety.sh
scripts/check-sun-comments.sh
sun fmt --check src cmd tests examples
sun -c sun-config.json
echo "built build/sun_serve, build/sun_serve.moon and the test binaries"
