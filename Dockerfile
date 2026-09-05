# syntax=docker/dockerfile:1
#
# Two stages share this file. "toolchain" holds only what scripts/build.sh
# and scripts/test.sh need and is what CI builds. "dev" adds the editor,
# git, and cross-compilation tools for the devcontainer.

FROM ubuntu:26.04 AS toolchain

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC

# curl and certificates fetch the compiler below; the openssl tool mints the
# certificates the TLS tests use and acts as their client.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl make nghttp2-client openssl \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# The musl toolchain provides the libstdc++ needed by Sun's static link mode.
# Use musl.cc's GitHub mirror because the main download host is unreliable.
RUN mkdir -p /opt/cross \
 && cd /tmp \
 && f="x86_64-linux-musl-cross.tgz" \
 && curl -fSL --connect-timeout 10 --max-time 300 \
      --retry 3 --retry-all-errors --retry-delay 2 \
      -o "$f" "https://github.com/musl-cc/musl.cc/releases/download/v0.0.1/$f" \
 && echo "c5d410d9f82a4f24c549fe5d24f988f85b2679b452413a9f7e5f7b956f2fe7ea  $f" | sha256sum -c - \
 && tar xzf "$f" -C /opt/cross \
 && rm -f "$f"
ENV PATH="/opt/cross/x86_64-linux-musl-cross/bin:${PATH}"

ARG ZLIB_VERSION=1.3.2
ARG ZLIB_SHA256=bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16

# Build zlib with the same musl compiler Sun uses for static binaries.
RUN curl -fSL --connect-timeout 10 --max-time 300 \
      --retry 3 --retry-all-errors --retry-delay 2 \
      -o /tmp/zlib.tar.gz \
      "https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz" \
 && echo "${ZLIB_SHA256}  /tmp/zlib.tar.gz" | sha256sum -c - \
 && mkdir -p /tmp/zlib-src \
 && tar xzf /tmp/zlib.tar.gz -C /tmp/zlib-src --strip-components=1 \
 && cd /tmp/zlib-src \
 && CC=x86_64-linux-musl-gcc ./configure --static \
      --prefix=/opt/cross/x86_64-linux-musl-cross/x86_64-linux-musl \
 && make -j2 \
 && make install \
 && test -f /opt/cross/x86_64-linux-musl-cross/x86_64-linux-musl/lib/libz.a \
 && rm -rf /tmp/zlib-src /tmp/zlib.tar.gz

# Refresh the rolling compiler per workflow run, after the cached native tools.
ARG SUN_REFRESH=local
RUN echo "Sun package refresh: ${SUN_REFRESH}" \
 && curl -fsSL -o /tmp/sun.deb \
      https://github.com/namo-robotics/sun/releases/download/dev/sun_0.dev_amd64.deb \
 && apt-get update \
 && apt-get install -y --no-install-recommends /tmp/sun.deb \
 && sun --version \
 && rm -f /tmp/sun.deb \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Default ports of the sun_serve command (HTTP/h2c, HTTPS/h2) and the example. The
# devcontainer runs with host networking, so these are reachable from the
# host directly; plain `docker run` needs -p or --network=host.
EXPOSE 8080 8443

CMD ["/bin/bash"]


FROM toolchain AS dev

RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core tools
    git python3 \
    # Quality-of-life tools
    vim less htop wget unzip \
    openssh-client \
    sudo \
    bash-completion \
    locales \
    # Cross-compilation to AArch64: toolchain+sysroot to link `sun --target
    # aarch64-linux-gnu -c` output, qemu-user to run the result on x86
    # (qemu-aarch64 -L /usr/aarch64-linux-gnu <binary>). Waits on aarch64
    # builds of the stdlib and TLS moons before it is useful.
    g++-aarch64-linux-gnu \
    qemu-user \
    && locale-gen en_US.UTF-8 \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# GitHub CLI from the official apt repo (newer than the Ubuntu archive build)
RUN mkdir -p -m 755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Grant sudo to existing ubuntu user (UID 1000 already exists in Ubuntu 24.04+)
RUN echo "ubuntu ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu \
    && chmod 0440 /etc/sudoers.d/ubuntu

# Eager-load git completion (needed for alias completion)
RUN echo '[ -f /usr/share/bash-completion/completions/git ] && . /usr/share/bash-completion/completions/git' > /etc/profile.d/git-completion.sh
