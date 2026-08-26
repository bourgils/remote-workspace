# syntax=docker/dockerfile:1

ARG DEBIAN_RELEASE=bookworm
ARG NODE_VERSION=22
ARG PROOT_VERSION=5.4.0
ARG TTYD_VERSION=1.7.7

# QMD uses Node native modules, so build it with npm instead of Bun.
FROM node:${NODE_VERSION}-${DEBIAN_RELEASE} AS qmd
ARG QMD_VERSION=latest
RUN npm_config_nodedir=/usr/local npm install -g "@tobilu/qmd@${QMD_VERSION}" \
 && qmd --version

# Bookworm ships PRoot 5.1.0, which is incompatible with recent kernels.
FROM node:${NODE_VERSION}-${DEBIAN_RELEASE} AS proot
ARG PROOT_VERSION
RUN sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list.d/debian.sources \
 && apt-get -o Acquire::Retries=10 update \
 && apt-get -o Acquire::Retries=10 install -y --no-install-recommends libtalloc-dev \
 && rm -rf /var/lib/apt/lists/* \
 && git clone --branch "v${PROOT_VERSION}" --depth=1 --recurse-submodules --shallow-submodules \
      https://github.com/proot-me/proot.git /tmp/proot \
 && make -C /tmp/proot/src -f GNUmakefile \
 && strip /tmp/proot/src/proot \
 && /tmp/proot/src/proot --kill-on-exit -0 /bin/true

# This stage is the persistent guest userspace template.
FROM node:${NODE_VERSION}-${DEBIAN_RELEASE}-slim AS guest
ARG OPENCODE_VERSION=latest
ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash ca-certificates curl fzf git jq less locales nano openssh-client \
      procps ripgrep sudo unzip vim-tiny wget zsh \
 && rm -rf /var/lib/apt/lists/*

# Bun is used as the persistent package runtime for OpenCode.
RUN curl -fsSL https://bun.sh/install | bash \
 && /root/.bun/bin/bun install -g "opencode-ai@${OPENCODE_VERSION}"

COPY --from=qmd /usr/local/lib/node_modules/@tobilu/qmd /usr/local/lib/node_modules/@tobilu/qmd
RUN ln -s /bin/true /usr/local/bin/xdg-open \
 && ln -s ../lib/node_modules/@tobilu/qmd/bin/qmd /usr/local/bin/qmd \
 && qmd --version

# Oh My Zsh without running its interactive installer.
RUN git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /root/.oh-my-zsh \
 && cat > /root/.zshrc <<'ZSHRC'
export ZSH="$HOME/.oh-my-zsh"
plugins=(git)
ZSH_THEME="robbyrussell"
export PATH="$HOME/.bun/bin:$PATH"
source "$ZSH/oh-my-zsh.sh"
ZSHRC

COPY runtime/bin/workspace-url /usr/local/bin/workspace-url
RUN chmod +x /usr/local/bin/workspace-url

RUN cat > /etc/profile.d/workspace.sh <<'EOF_PROFILE'
export PATH="$HOME/.bun/bin:$PATH"
export WORKSPACE_PATH="${WORKSPACE_PATH:-/workspace}"
if [ -n "${WORKSPACE_NAME:-}" ]; then
  export WORKSPACE_NAME
fi
EOF_PROFILE

# Outer image: only the launcher, web PTY, and PRoot.
FROM debian:${DEBIAN_RELEASE}-slim AS runtime
ARG TARGETARCH
ARG TTYD_VERSION
ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl libtalloc2 python3 \
 && rm -rf /var/lib/apt/lists/* \
 && case "$TARGETARCH" in \
      amd64) ttyd_arch=x86_64; ttyd_sha256=8a217c968aba172e0dbf3f34447218dc015bc4d5e59bf51db2f2cd12b7be4f55 ;; \
      arm64) ttyd_arch=aarch64; ttyd_sha256=b38acadd89d1d396a0f5649aa52c539edbad07f4bc7348b27b4f4b7219dd4165 ;; \
      *) echo "unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac \
 && curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${ttyd_arch}" \
      -o /usr/local/bin/ttyd \
 && echo "${ttyd_sha256}  /usr/local/bin/ttyd" | sha256sum -c - \
 && chmod +x /usr/local/bin/ttyd

COPY --from=proot /tmp/proot/src/proot /usr/local/bin/proot
COPY --from=guest / /opt/workspace-rootfs-template/
COPY runtime/bin/ /usr/local/bin/
RUN chmod +x /usr/local/bin/workspace-*

ENV WORKSPACE_NAME=workspace \
    WORKSPACE_PATH=/workspace \
    STATE_PATH=/state \
    OPENCODE_PORT=4096 \
    SHELL_PORT=7681 \
    TZ=UTC

VOLUME ["/state", "/workspace"]
EXPOSE 4096 7681
ENTRYPOINT ["/usr/local/bin/workspace-entrypoint"]
