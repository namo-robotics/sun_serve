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
# Named builds include their required library; unexported applications are opt-in.
sun build --config sun-config.json --entrypoint server
sun build --config sun-config.json --entrypoint hello_handler
build_root=$(sun describe --config sun-config.json --field build_root)
# Keep the public paths used by tests, examples, benchmarks, and release packaging.
cp "$build_root/sun_serve.moon" build/sun_serve.moon
cp "$build_root/sun_serve_test" build/sun_serve_lib_test
cp "$build_root/server" build/sun_serve
cp "$build_root/server_test" build/sun_serve_test
cp "$build_root/hello_handler" "$build_root/hello_handler_test" build/
echo "built build/sun_serve, build/sun_serve.moon and the test binaries"
