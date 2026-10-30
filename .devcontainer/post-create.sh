#!/usr/bin/env bash
# Prepare a workspace cache without privilege escalation in the server container.
# Container startup preserves the compiler and project dependencies in the image.
set -euo pipefail

source /etc/os-release
if [[ "$ID" != ubuntu || "$VERSION_ID" != 26.04 ]]; then
    echo 'The Sun devcontainer template requires Ubuntu 26.04.' >&2
    exit 1
fi

cache_dir="${CCACHE_DIR:-$HOME/.cache/ccache}"
mkdir -p "$cache_dir"
test -w "$cache_dir"
