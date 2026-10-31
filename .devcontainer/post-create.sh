#!/usr/bin/env bash
set -euo pipefail

GITHUB_ENV_FILE="$HOME/.dc/github/.env"
BRAVE_ENV_FILE="$HOME/.dc/brave/.env"
DEV_USER="${SUDO_USER:-$(id -un)}"

# Read the GitHub token in a subshell so the rest of the script's child
# processes do not inherit it. The .bashrc blocks further down load the env
# files for future interactive shells.
github_token=""
if [ -f "$GITHUB_ENV_FILE" ]; then
  echo "Loading GitHub env ($GITHUB_ENV_FILE)..."
  github_token="$(
    set -a
    . "$GITHUB_ENV_FILE"
    printf '%s' "${GITHUB_TOKEN:-}"
  )"
fi

echo "Configuring opencode directories..."
for dir in \
  "$HOME/.local/share/opencode" \
  "$HOME/.config/opencode" \
  "$HOME/.local/state/opencode" \
  "$HOME/.local/share/opentui/tree-sitter" \
  "$HOME/.local/share/uv" \
  "$HOME/.local/state/nvim" \
  "$HOME/.local/share/nvim" \
  "$HOME/.local/bin"; do
  sudo mkdir -p "$dir"
done

# Repair ownership for existing volumes. Fresh volumes inherit developer
# ownership from the pre-created directories in the Dockerfile. Chown the
# parent directories too so tools can create new files under them.
sudo chown -R --no-dereference "$DEV_USER:$DEV_USER" "$HOME/.local" "$HOME/.config" /worktrees

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

# yq is installed and pinned in the Dockerfile; verify it is available.
echo "Verifying yq..."
yq --version

if ! grep -qF '# --- github env ---' "$HOME/.bashrc" 2>/dev/null; then
  cat >>"$HOME/.bashrc" <<EOF

# --- github env ---
GITHUB_ENV_FILE="$GITHUB_ENV_FILE"
if [ -f "$GITHUB_ENV_FILE" ]; then
  set -a
  . "$GITHUB_ENV_FILE"
  set +a
fi
EOF
fi

if ! grep -qF '# --- brave env ---' "$HOME/.bashrc" 2>/dev/null; then
  cat >>"$HOME/.bashrc" <<EOF

# --- brave env ---
BRAVE_ENV_FILE="$BRAVE_ENV_FILE"
if [ -f "$BRAVE_ENV_FILE" ]; then
  set -a
  . "$BRAVE_ENV_FILE"
  set +a
fi
EOF
fi

echo "Logging into Helm registry with GitHub token..."
if [ -n "$github_token" ]; then
  printf '%s' "$github_token" | helm registry login ghcr.io -u unused --password-stdin 2>/dev/null || true
fi

echo "Setting up kubectl aliases and completion..."
if ! grep -qF '# --- kubectl aliases ---' "$HOME/.bashrc" 2>/dev/null; then
  cat >>"$HOME/.bashrc" <<'EOF'

# --- kubectl aliases ---
k() {
  case "$1" in
    ns) shift; kubens "$@" ;;
    ctx) shift; kubectx "$@" ;;
    *) kubectl "$@" ;;
  esac
}
if command -v kubectl >/dev/null 2>&1; then
  source <(kubectl completion bash 2>/dev/null)
  complete -F __start_kubectl k
fi
EOF
fi

mkdir -p "$HOME/.local/bin"
if uv tool list 2>/dev/null | grep -q '^specify-cli ' && [ -x "$HOME/.local/bin/specify" ]; then
  echo "specify-cli already installed."
else
  echo "Installing specify-cli..."
  uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@v0.16.4
fi

echo 'Dev container setup complete.'
