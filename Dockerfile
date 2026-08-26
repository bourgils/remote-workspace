# syntax=docker/dockerfile:1

ARG DEBIAN_RELEASE=bookworm

# This stage is the persistent guest userspace template.
FROM debian:${DEBIAN_RELEASE}-slim AS guest
ARG OPENCODE_VERSION=latest
ARG QMD_VERSION=latest
ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash ca-certificates curl fzf git jq less locales nano openssh-client \
      procps ripgrep sudo unzip vim-tiny wget zsh \
 && rm -rf /var/lib/apt/lists/*

# Bun is used as the persistent package runtime for OpenCode and qmd.
RUN curl -fsSL https://bun.sh/install | bash \
 && /root/.bun/bin/bun install -g "opencode-ai@${OPENCODE_VERSION}" "@tobilu/qmd@${QMD_VERSION}"

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
ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl proot python3 ttyd \
 && rm -rf /var/lib/apt/lists/*

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
