FROM debian:bookworm-slim

# Avoid warnings by switching to noninteractive for the install
ENV DEBIAN_FRONTEND=noninteractive

USER root

ARG USERNAME=developer
ARG USER_UID=1000
ARG USER_GID=$USER_UID
ARG YQ_VERSION=v4.54.1
ARG OPENCODE_VERSION=2.1.4

# Install core development tools stripped out of the slim image
RUN apt-get update && apt-get install -y --no-install-recommends \
  git \
  curl \
  ca-certificates \
  sudo \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Create a non-root user to avoid running everything as root
RUN groupadd --gid $USER_GID $USERNAME \
  && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
  # Add sudo support for the non-root user
  && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
  && chmod 0440 /etc/sudoers.d/$USERNAME


# Install yq (mikefarah/yq v4) at a pinned version. dpkg's arch names match
# the release asset names for the platforms devcontainers run on (amd64/arm64).
RUN arch="$(dpkg --print-architecture)" \
  && curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${arch}" \
  -o /usr/local/bin/yq \
  && chmod +x /usr/local/bin/yq \
  && yq --version

USER $USERNAME

# Install OpenCode V2 as the vscode user.
RUN curl -fsSL https://opencode.ai/v2/install | \
  bash -s -- --version "${OPENCODE_VERSION}" --no-modify-path \
  && /home/${USERNAME}/.opencode/bin/opencode --version

# Revert frontend status back to default
ENV DEBIAN_FRONTEND=dialog
