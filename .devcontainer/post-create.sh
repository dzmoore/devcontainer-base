#!/usr/bin/env bash
set -euo pipefail

GITHUB_ENV_FILE="$HOME/.dc/github/.env"
BRAVE_ENV_FILE="$HOME/.dc/brave/.env"
DEV_USER="${SUDO_USER:-$(id -un)}"

# --- timezone ---
# The image writes TZ from ARG TZ. A project can override it with containerEnv.TZ;
# reconcile /etc/localtime so clean-environment consumers (sudo -i, su -, cron,
# dockerd) see the same zone as normal processes.
if [ -z "${TZ+x}" ]; then
  TZ="$(cat /etc/timezone 2>/dev/null || true)"
fi
if [ -z "$TZ" ]; then
  echo "Invalid TZ: TZ is empty or unset, and /etc/timezone is empty or absent" >&2
  exit 1
fi
if [[ ! "$TZ" =~ ^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+)*$ ]]; then
  echo "Invalid TZ '$TZ': expected an IANA zone such as America/Los_Angeles" >&2
  exit 1
fi
case "$TZ" in
  localtime|leapseconds|posixrules)
    echo "Invalid TZ '$TZ': not an IANA zone" >&2
    exit 1
    ;;
esac
zone="/usr/share/zoneinfo/$TZ"
if [ ! -f "$zone" ]; then
  echo "Invalid TZ '$TZ': $zone is not a zone file" >&2
  exit 1
fi
resolved="$(readlink -f -- "$zone" 2>/dev/null || true)"
case "$resolved" in
  /usr/share/zoneinfo/*) ;;
  *)
    echo "Invalid TZ '$TZ': $zone does not resolve inside /usr/share/zoneinfo" >&2
    exit 1
    ;;
esac
if ! head -c 4 "$resolved" | grep -q '^TZif'; then
  echo "Invalid TZ '$TZ': $resolved is not a TZif zone file" >&2
  exit 1
fi
export TZ
current="$(readlink -f /etc/localtime 2>/dev/null || true)"
if [ -z "$current" ] || [ "$current" != "$resolved" ]; then
  if [ -d /etc/localtime ]; then
    echo "Refusing to replace /etc/localtime: it is a directory" >&2
    exit 1
  fi
  sudo -n ln -sfn "$zone" /etc/localtime
fi
if [ "$(cat /etc/timezone 2>/dev/null || true)" != "$TZ" ]; then
  printf '%s\n' "$TZ" | sudo -n tee /etc/timezone >/dev/null
fi

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
sudo chown -R --no-dereference "$DEV_USER:$DEV_USER" "$HOME/.local" "$HOME/.config" "$HOME/.kube"

# --- multi-repo workspace ---
# Clones live in the bind-mounted workspace so they persist without a named
# volume. /worktrees is a compatibility symlink.
echo "Configuring multi-repo workspace..."
mkdir -p /workspace/repos
if [ -L /worktrees ]; then
  if [ "$(readlink /worktrees)" != "/workspace/repos" ]; then
    sudo -n rm -f /worktrees
    sudo -n ln -s /workspace/repos /worktrees
  fi
elif mountpoint -q /worktrees 2>/dev/null; then
  echo "WARNING: /worktrees is an old volume mountpoint. Move its contents to" \
    "/workspace/repos, remove the worktrees volume from devcontainer.json, and" \
    "recreate the container. Then run 'git worktree repair' in each clone." >&2
elif [ -d /worktrees ]; then
  if [ -z "$(ls -A /worktrees 2>/dev/null)" ]; then
    sudo -n rmdir /worktrees
    sudo -n ln -s /workspace/repos /worktrees
  else
    echo "WARNING: /worktrees is a non-empty directory. Move its contents to" \
      "/workspace/repos and recreate the container. Then run 'git worktree repair'" \
      "in each clone; /worktrees was left untouched." >&2
  fi
else
  sudo -n ln -s /workspace/repos /worktrees
fi

# --- opencode host secrets ---
# The host overlay references secrets as {file:/etc/opencode/...}. Validate
# those references before OpenCode starts; never print the file contents.
while IFS= read -r secret; do
  if [ ! -f "$secret" ]; then
    echo "Missing host secret: $secret" >&2
    exit 1
  fi
  if [ ! -r "$secret" ]; then
    echo "Unreadable host secret: $secret" >&2
    exit 1
  fi
  if [ ! -s "$secret" ]; then
    echo "Empty host secret: $secret" >&2
    exit 1
  fi
done < <(
  find /etc/opencode -type f \( -name opencode.json -o -name opencode.jsonc \) -print0 2>/dev/null |
    xargs -0 -r grep -hoE '\{file:/etc/opencode/[^}]+\}' 2>/dev/null |
    sed -e 's/^{file://' -e 's/}$//' |
    sort -u
)

# --- opencode control plane ---
OC_SRC="/workspace/.opencode"
if [ -d "$OC_SRC" ]; then
  mkdir -p "$HOME/.config/opencode/agents" "$HOME/.config/opencode/skills"
  if [ ! -e "$HOME/.config/opencode/opencode.json" ] || [ -L "$HOME/.config/opencode/opencode.json" ]; then
    ln -sfn "$OC_SRC/opencode.global.json" "$HOME/.config/opencode/opencode.json"
  fi
  for src in "$OC_SRC"/agents/*.md; do
    [ -e "$src" ] || continue
    dest="$HOME/.config/opencode/agents/$(basename "$src")"
    if [ ! -e "$dest" ] || [ -L "$dest" ]; then
      ln -sfn "$src" "$dest"
    fi
  done
  for src in "$OC_SRC"/skills/*; do
    [ -d "$src" ] || continue
    dest="$HOME/.config/opencode/skills/$(basename "$src")"
    if [ ! -e "$dest" ] || [ -L "$dest" ]; then
      ln -sfn "$src" "$dest"
    fi
  done
  # Remove stale links that point into the control plane but whose source is gone.
  for link in "$HOME/.config/opencode/agents"/* "$HOME/.config/opencode/skills"/*; do
    [ -L "$link" ] || continue
    case "$(readlink "$link")" in
      "$OC_SRC"/*)
        [ -e "$link" ] || rm -f "$link"
        ;;
    esac
  done
fi

echo "Installing GitHub App helper commands..."
for helper in gh-app-token gh-app; do
  src="/workspace/.devcontainer/bin/$helper"
  if [ -x "$src" ]; then
    ln -sfn "$src" "$HOME/.local/bin/$helper"
  fi
done
echo "Installing repo helper command..."
src="/workspace/.devcontainer/bin/repo"
if [ -x "$src" ]; then
  ln -sfn "$src" "$HOME/.local/bin/repo"
fi

# Kubernetes client-go locks every file listed in KUBECONFIG. On macOS
# VirtioFS bind mounts the lock file can be created with mode 000, which makes
# kind fail with "config.lock: permission denied". Keep the writable default
# kubeconfig on the container volume and do not include a workspace path in
# KUBECONFIG; merge a project-local config manually if needed.
echo "Configuring container-local kubeconfig..."
mkdir -p "$HOME/.kube"
chmod 700 "$HOME/.kube"
touch "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"
rm -f "$HOME/.kube/config.lock"

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
  printf '%s' "$github_token" | timeout 15 helm registry login ghcr.io -u unused --password-stdin 2>/dev/null || true
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

echo "Setting up Helm completion..."
if ! grep -qF '# --- helm completion ---' "$HOME/.bashrc" 2>/dev/null; then
  cat >>"$HOME/.bashrc" <<'EOF'

# --- helm completion ---
if command -v helm >/dev/null 2>&1; then
  source <(helm completion bash 2>/dev/null)
fi
EOF
fi

echo "Verifying build-time tools..."
nvim --version >/dev/null
starship --version >/dev/null
glow --version >/dev/null
kubectl version --client >/dev/null
helm version --template '{{.Version}}' >/dev/null

if ! grep -qF '# --- devcontainer aliases ---' "$HOME/.bashrc" 2>/dev/null; then
  cat >>"$HOME/.bashrc" <<'EOF'

# --- devcontainer aliases ---
if [ -f /workspace/.devcontainer/aliases.sh ]; then
  . /workspace/.devcontainer/aliases.sh
fi
EOF
fi

if ! grep -qF '# --- terminal paste ---' "$HOME/.bashrc" 2>/dev/null; then
  cat >>"$HOME/.bashrc" <<'EOF'

# --- terminal paste ---
# Ghostty and some IDE terminals advertise a TERM whose terminfo entry is not
# present in the container (for example xterm-ghostty). Fall back to a known
# 256-color terminfo, and harden readline/flow control for reliable paste.
if [ -t 0 ] && [ -t 1 ]; then
  if [ -z "${TERM:-}" ] || [ "$TERM" = "dumb" ] || [ "$TERM" = "xterm" ] || ! infocmp "$TERM" >/dev/null 2>&1; then
    export TERM=xterm-256color
  fi
  stty -ixon 2>/dev/null || true
  bind 'set enable-bracketed-paste on' 2>/dev/null || true
fi
EOF
fi

if ! grep -qF '# --- starship prompt ---' "$HOME/.bashrc" 2>/dev/null; then
  cat >>"$HOME/.bashrc" <<'EOF'

# --- starship prompt ---
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi
EOF
fi

echo 'Dev container setup complete.'
