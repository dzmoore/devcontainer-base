FROM debian:bookworm-slim

# Avoid warnings by switching to noninteractive for the install
ENV DEBIAN_FRONTEND=noninteractive

USER root

ARG USERNAME=developer
ARG USER_UID=1000
ARG USER_GID=$USER_UID
ARG YQ_VERSION=v4.54.1
ARG OPENCODE_VERSION=2.2.5
ARG NVIM_VERSION=v0.12.6
ARG STARSHIP_VERSION=v1.27.0
ARG SPECIFY_VERSION=v0.16.4

# Install core development tools stripped out of the slim image.
# libatomic1 is required by the official Node.js arm64 binaries; openssh-client
# is needed for SSH git remotes; ripgrep avoids OpenCode's arm64 fallback path.
# python3/pipx are used to install the spec-kit CLI at build time.
RUN apt-get update && apt-get install -y --no-install-recommends \
  git \
  curl \
  ca-certificates \
  sudo \
  libatomic1 \
  openssh-client \
  ripgrep \
  locales \
  unzip \
  zip \
  python3 \
  python3-venv \
  pipx \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Create a non-root user to avoid running everything as root. The shell must be
# bash: several Dev Container features run `su <user> -c` snippets that use bash
# builtins (for example the Node feature's `source nvm.sh`).
RUN groupadd --gid $USER_GID $USERNAME \
  && useradd --uid $USER_UID --gid $USER_GID -m --shell /bin/bash $USERNAME \
  # Add sudo support for the non-root user
  && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
  && chmod 0440 /etc/sudoers.d/$USERNAME

# Generate the UTF-8 locale used by the dev container.
RUN sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
  && locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 \
  LC_ALL=en_US.UTF-8

# Pre-create every named-volume mount target so a fresh volume inherits
# developer ownership instead of initializing as root-owned. Chown the parent
# directories too; otherwise .local and .config are left root-owned.
RUN mkdir -p \
  /home/$USERNAME/.local/share/opencode \
  /home/$USERNAME/.local/state/opencode \
  /home/$USERNAME/.local/share/opentui \
  /home/$USERNAME/.local/share/uv \
  /home/$USERNAME/.local/state/nvim \
  /home/$USERNAME/.local/share/nvim \
  /home/$USERNAME/.config/opencode \
  /worktrees \
  && chown -R $USERNAME:$USERNAME \
  /home/$USERNAME/.local \
  /home/$USERNAME/.config \
  /worktrees


# Install yq (mikefarah/yq v4) at a pinned version. dpkg's arch names match
# the release asset names for the platforms devcontainers run on (amd64/arm64).
RUN arch="$(dpkg --print-architecture)" \
  && curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${arch}" \
  -o /usr/local/bin/yq \
  && chmod +x /usr/local/bin/yq \
  && yq --version

# Install Neovim from the official release tarball. The tarball is
# self-contained apart from libc/libm/libgcc, which bookworm already provides.
RUN arch="$(dpkg --print-architecture)" \
  && case "$arch" in \
       amd64) nvim_arch=x86_64 ;; \
       arm64) nvim_arch=arm64 ;; \
       *) echo "Unsupported architecture for Neovim: $arch" >&2; exit 1 ;; \
     esac \
  && curl -fsSL "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-${nvim_arch}.tar.gz" \
    -o /tmp/nvim.tar.gz \
  && tar -xzf /tmp/nvim.tar.gz -C /opt \
  && mv "/opt/nvim-linux-${nvim_arch}" /opt/nvim \
  && ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim \
  && rm /tmp/nvim.tar.gz \
  && nvim --version | head -1

# Install Starship (pinned) for the interactive bash prompt.
RUN curl -fsSL https://starship.rs/install.sh -o /tmp/starship-install.sh \
  && sh /tmp/starship-install.sh -y --bin-dir /usr/local/bin --version "${STARSHIP_VERSION}" \
  && rm /tmp/starship-install.sh \
  && starship --version | head -1

# Install the spec-kit CLI at build time so post-create only has to verify it.
RUN PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin \
    pipx install "git+https://github.com/github/spec-kit.git@${SPECIFY_VERSION}" \
  && specify --help >/dev/null

USER $USERNAME

# Install OpenCode V2 as the developer user.
RUN curl -fsSL https://opencode.ai/v2/install | \
  bash -s -- --version "${OPENCODE_VERSION}" --no-modify-path \
  && /home/${USERNAME}/.opencode/bin/opencode --version

# Revert frontend status back to default
ENV DEBIAN_FRONTEND=dialog
