#!/usr/bin/env bash
# Build the library, the command, the example, and their test binaries into
# build/. The compiler hashes every input and leaves an artifact alone when
# nothing it was built from has changed, so repeat runs are cheap.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
sun --version
scripts/check-sun-safety.sh
scripts/check-sun-comments.sh
sun fmt --check src cmd tests examples
sun -c sun-config.json
echo "built build/sun_serve, build/sun_serve.moon and the test binaries"
