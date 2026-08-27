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
ARG OPENCODE_VERSION=1.18.23
ENV DEBIAN_FRONTEND=noninteractive
ENV BUN_INSTALL=/opt/bun
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash ca-certificates curl fzf git jq less locales nano openssh-client \
      procps ripgrep sudo unzip vim-tiny wget zsh \
 && rm -rf /var/lib/apt/lists/*

# Bun and OpenCode live outside the workspace-backed home.
RUN curl -fsSL https://bun.sh/install | bash \
 && /opt/bun/bin/bun install -g "opencode-ai@${OPENCODE_VERSION}"

COPY --from=qmd /usr/local/lib/node_modules/@tobilu/qmd /usr/local/lib/node_modules/@tobilu/qmd
RUN ln -s /bin/true /usr/local/bin/xdg-open \
 && ln -s ../lib/node_modules/@tobilu/qmd/bin/qmd /usr/local/bin/qmd \
 && qmd --version

# Oh My Zsh without running its interactive installer.
RUN git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /opt/oh-my-zsh \
 && git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git \
      /opt/oh-my-zsh/custom/plugins/zsh-autosuggestions \
 && git clone --depth=1 https://github.com/zsh-users/zsh-completions.git \
      /opt/oh-my-zsh/custom/plugins/zsh-completions \
 && git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git \
      /opt/oh-my-zsh/custom/plugins/zsh-syntax-highlighting \
 && mkdir -p /home/workspace /opt/workspace-home-template \
 && sed -i 's|^root:x:0:0:root:/root:|root:x:0:0:root:/home/workspace:|' /etc/passwd \
 && test "$(getent passwd root | cut -d: -f6)" = /home/workspace \
 && cat > /opt/workspace-home-template/.zshrc <<'ZSHRC'
export ZSH="/opt/oh-my-zsh"
export ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH/custom}"

ZSH_THEME="robbyrussell"
fpath=("$ZSH_CUSTOM/plugins/zsh-completions/src" $fpath)
plugins=(git sudo zsh-autosuggestions)

export BUN_INSTALL="/opt/bun"
export PATH="$BUN_INSTALL/bin:$PATH"
source "$ZSH/oh-my-zsh.sh"

setopt PROMPT_SUBST COMPLETE_IN_WORD HIST_IGNORE_DUPS SHARE_HISTORY
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

autoload -Uz add-zsh-hook vcs_info
add-zsh-hook precmd vcs_info
zstyle ':vcs_info:git:*' formats '%F{yellow}%b%f'
zstyle ':vcs_info:git:*' actionformats '%F{yellow}%b|%a%f'
PROMPT='%F{magenta}%n@%m%f %F{green}➜%f %F{cyan}%~%f ${vcs_info_msg_0_} '

HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000

alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'

export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

source "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
ZSHRC

COPY runtime/bin/workspace-url /usr/local/bin/workspace-url
RUN chmod +x /usr/local/bin/workspace-url

RUN cat >> /etc/profile <<'EOF_PROFILE'
export BUN_INSTALL="/opt/bun"
export PATH="$BUN_INSTALL/bin:$PATH"
export WORKSPACE_PATH="${WORKSPACE_PATH:-$HOME}"
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
COPY --from=guest /opt/workspace-home-template/ /opt/workspace-home-template/
COPY runtime/bin/ /usr/local/bin/
RUN chmod +x /usr/local/bin/workspace-*

ENV WORKSPACE_NAME=workspace \
    WORKSPACE_HOME=/home/workspace \
    WORKSPACE_SOURCE=/mnt/workspace \
    STATE_PATH=/state \
    OPENCODE_PORT=4096 \
    SHELL_PORT=7681 \
    TZ=UTC

VOLUME ["/state", "/mnt/workspace"]
EXPOSE 4096 7681
ENTRYPOINT ["/usr/local/bin/workspace-entrypoint"]
