#!/usr/bin/env bash
set -euo pipefail

GITHUB_ENV_FILE="$HOME/.dc/github/.env"
BRAVE_ENV_FILE="$HOME/.dc/brave/.env"

echo "Generating locale for proper Unicode width detection..."
# Generate locale for proper Unicode width detection (markdown tables, box-drawing)
sudo locale-gen en_US.UTF-8 2>/dev/null || true

echo "Configuring opencode directories..."
OPENDIR=/home/vscode/.local/share/opencode
sudo mkdir -p "$OPENDIR"
if [ "$(stat -c '%U' "$OPENDIR" 2>/dev/null)" != "vscode" ]; then
  sudo chown -R vscode:vscode "$OPENDIR"
fi

CONFIGDIR=/home/vscode/.config/opencode
sudo mkdir -p "$CONFIGDIR"
if [ "$(stat -c '%U' "$CONFIGDIR" 2>/dev/null)" != "vscode" ]; then
  sudo chown -R vscode:vscode "$CONFIGDIR"
fi

STATEDIR=/home/vscode/.local/state/opencode
sudo mkdir -p "$STATEDIR"
if [ "$(stat -c '%U' "$STATEDIR" 2>/dev/null)" != "vscode" ]; then
  sudo chown -R vscode:vscode "$STATEDIR"
fi

# Tree-sitter cache dir for @opentui/core markdown rendering
OPENTUI_DIR=/home/vscode/.local/share/opentui
sudo mkdir -p "$OPENTUI_DIR/tree-sitter"
if [ "$(stat -c '%U' "$OPENTUI_DIR" 2>/dev/null)" != "vscode" ]; then
  sudo chown -R vscode:vscode "$OPENTUI_DIR"
fi

echo "Installing yq..."
case "$(uname -s)" in
Linux*) YQ_OS=linux ;;
Darwin*) YQ_OS=darwin ;;
MINGW* | MSYS* | CYGWIN*) YQ_OS=windows ;;
*)
  echo "Unknown OS: $(uname -s)"
  exit 1
  ;;
esac

case "$(uname -m)" in
x86_64 | amd64) YQ_ARCH=amd64 ;;
arm64 | aarch64) YQ_ARCH=arm64 ;;
armv7l | armv6l) YQ_ARCH=arm ;;
i386 | i686) YQ_ARCH=386 ;;
*)
  echo "Unknown architecture: $(uname -m)"
  exit 1
  ;;
esac

YQ_PLATFORM="${YQ_OS}_${YQ_ARCH}"
sudo curl -Lo /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_${YQ_PLATFORM}"
sudo chmod +x /usr/local/bin/yq

# VS Code's remote-containers integration injects a docker credential helper
# (credsStore) into ~/.docker/config.json that only works inside a live VS Code
# session. In other shells (agents, cron) the helper fails and poisons registry
# auth, so anonymous pulls of public images fail with "denied". Strip it so
# docker falls back to anonymous access for public registries.
DOCKER_CFG="$HOME/.docker/config.json"
if [ -f "$DOCKER_CFG" ] && yq -e '.credsStore' "$DOCKER_CFG" >/dev/null 2>&1; then
  yq -i 'del(.credsStore)' "$DOCKER_CFG"
  echo "Removed broken docker credsStore from $DOCKER_CFG"
fi

if [ -e "$GITHUB_ENV_FILE" ]; then
  echo "Loading GitHub env ($GITHUB_ENV_FILE)..."

  cat >>"$HOME/.bashrc" <<EOF
GITHUB_ENV_FILE="$GITHUB_ENV_FILE"
EOF

  cat >>"$HOME/.bashrc" <<'EOF'
export $(grep -v '^#' "$GITHUB_ENV_FILE" | xargs)
EOF
fi

if [ -e "$BRAVE_ENV_FILE" ]; then
  echo "Loading Brave env ($BRAVE_ENV_FILE)..."
  cat >>"$HOME/.bashrc" <<EOF
BRAVE_ENV_FILE="$BRAVE_ENV_FILE"
EOF

  cat >>"$HOME/.bashrc" <<'EOF'
export $(grep -v '^#' "$BRAVE_ENV_FILE" | xargs)
EOF
fi

# echo "Installing vim..."
# sudo apt-cache update
# sudo apt-get install -y vim

echo "Logging into Helm registry with GitHub token..."
if [ -n "${GITHUB_TOKEN:-}" ]; then
  echo "$GITHUB_TOKEN" | helm registry login ghcr.io -u unused --password-stdin 2>/dev/null || true
fi

echo "Setting up kubectl aliases and completion..."
if ! grep -q '# --- kubectl aliases' "$HOME/.bashrc" 2>/dev/null; then
  cat >>"$HOME/.bashrc" <<'EOF'

# --- kubectl aliases ---
k() {
  case "$1" in
    ns) shift; kubens "$@" ;;
    ctx) shift; kubectx "$@" ;;
    *) kubectl "$@" ;;
  esac
}
source <(kubectl completion bash 2>/dev/null)
complete -F __start_kubectl k
EOF
fi

source <(kubectl completion bash 2>/dev/null)
k() {
  case "$1" in
  ns)
    shift
    kubens "$@"
    ;;
  ctx)
    shift
    kubectx "$@"
    ;;
  *) kubectl "$@" ;;
  esac
}
complete -F __start_kubectl k

echo "Fixing uv tool install directories..."
# Fix permissions for uv tool install (directories may be owned by root from mounts)
sudo chown -R vscode:vscode /home/vscode/.local
mkdir -p /home/vscode/.local/bin

uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@v0.16.4

echo 'Run agent-platform-up to bootstrap the kagent stack.'
