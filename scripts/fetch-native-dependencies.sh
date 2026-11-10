#!/usr/bin/env bash
# Prepare the prebuilt libraries embedded in sun_serve.moon: zlib for WebSocket
# compression and OpenSSL for TLS. Sun runs this step before compiling the
# library and passes its selected build directory as the only argument.
#
# Download version-pinned Alpine Linux packages, verify their SHA-256 checksums,
# and extract their static x86_64 musl archives into <build-root>/native.
# Nothing is compiled or installed system-wide; sudo is not needed.
#
# Later runs verify and reuse the extracted archives. Verified packages stay in
# native/downloads so missing or damaged archives can be restored offline.
# Temporary extraction files are removed on exit. Download or extraction failures
# leave the previous archives in place. Update package versions and checksums
# together when adopting a newer release; builds never silently change versions.
#
# Requires curl, CA certificates, GNU tar, gzip, and standard coreutils tools.
# Usage: bash scripts/fetch-native-dependencies.sh /path/to/build-root
set -euo pipefail

PACKAGE_BASE=https://dl-cdn.alpinelinux.org/alpine/v3.24/main/x86_64
OPENSSL_PACKAGE=openssl-libs-static-3.5.9-r0.apk
OPENSSL_SHA256=1ff255d219f15604deb5b37d8bc55eacd3f722aa406ea036f241ed49bd586060
ZLIB_PACKAGE=zlib-static-1.4-r0.apk
ZLIB_SHA256=3e02130f63e764b969f14ae62fe1f50b58436f709895c9d9fa2b7496c98a03b5

# Return success only when the selected packages and all cached archives match.
cached_archives_are_valid() {
    [[ -f "$native_dir/.recipe" && -f "$native_dir/archives.sha256" ]] || return 1
    [[ "$(cat "$native_dir/.recipe")" == "$recipe" ]] || return 1
    [[ -f "$native_dir/libssl.a" && -f "$native_dir/libcrypto.a" &&
       -f "$native_dir/libz.a" ]] || return 1
    (cd "$native_dir" && sha256sum --check --status archives.sha256)
}

# Reuse a verified package or download it, then extract only the requested archives.
prepare_package() {
    local package=$1
    local checksum=$2
    shift 2
    local download="$native_dir/downloads/$package"

    if [[ ! -f "$download" ]] ||
       ! echo "$checksum  $download" | sha256sum --check --status; then
        echo "Downloading $package"
        curl --fail --silent --show-error --location \
            --connect-timeout 10 --max-time 300 --retry 3 --retry-all-errors \
            --output "$stage/download" "$PACKAGE_BASE/$package"
        echo "$checksum  $stage/download" | sha256sum --check --status || {
            echo "Checksum verification failed: $package" >&2
            exit 1
        }
        mv "$stage/download" "$download"
    fi

    # APK metadata includes attributes GNU tar does not need for static archives.
    tar --warning=no-unknown-keyword --extract --gzip --file "$download" \
        --directory "$stage" --no-same-owner "$@"
}

# Publish verified archives and record their checksums, writing the marker last.
publish_archives() {
    local archive
    for archive in libz.a libssl.a libcrypto.a; do
        if [[ ! -s "$stage/usr/lib/$archive" ]]; then
            echo "Package is missing a required archive: $archive" >&2
            exit 1
        fi
    done
    rm -f "$native_dir/.recipe"
    cp "$stage/usr/lib/libz.a" "$stage/usr/lib/libssl.a" \
        "$stage/usr/lib/libcrypto.a" "$native_dir/"
    (cd "$native_dir" && sha256sum libz.a libssl.a libcrypto.a > archives.sha256)
    echo "$recipe" > "$native_dir/.recipe"
}

# Cache identity depends on package contents, not edits to comments in this script.
if [[ $# != 1 ]]; then
    echo "Usage: $0 /path/to/build-root" >&2
    exit 2
fi
mkdir -p "$1/native"
native_dir=$(cd "$1/native" && pwd -P)
recipe="prebuilt-v1:$OPENSSL_SHA256:$ZLIB_SHA256"
if cached_archives_are_valid; then
    exit 0
fi

mkdir -p "$native_dir/downloads"
stage=$(mktemp -d "$native_dir/.extract.XXXXXX")
trap 'rm -rf "$stage"' EXIT

prepare_package "$OPENSSL_PACKAGE" "$OPENSSL_SHA256" usr/lib/libssl.a usr/lib/libcrypto.a
prepare_package "$ZLIB_PACKAGE" "$ZLIB_SHA256" usr/lib/libz.a
publish_archives
echo "Prepared prebuilt musl OpenSSL and zlib archives."
