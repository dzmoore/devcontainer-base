#!/usr/bin/env bash
# Host-side initialization for the Dev Container. Runs from initializeCommand
# before the container is created. It creates the host overlay directories and
# the multi-repo workspace, and never copies examples or overwrites files.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
HOST_CONFIG_DIR="${DEVCONTAINER_HOST_CONFIG_DIR:-$HOME/.devcontainer/opencode}"
example_dir="$project_root/.devcontainer/examples/opencode"

umask 077
mkdir -p "$HOST_CONFIG_DIR/secrets" "$HOST_CONFIG_DIR/agents" "$HOST_CONFIG_DIR/skills"
chmod 700 "$HOST_CONFIG_DIR" "$HOST_CONFIG_DIR/secrets"

umask 022
mkdir -p "$project_root/repos"

if git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
  exclude_path="$(git -C "$project_root" rev-parse --git-path info/exclude)"
  case "$exclude_path" in
    /*) ;;
    *) exclude_path="$project_root/$exclude_path" ;;
  esac
  mkdir -p "$(dirname "$exclude_path")"
  if ! grep -qxF 'repos/' "$exclude_path" 2>/dev/null; then
    printf '%s\n' 'repos/' >>"$exclude_path"
  fi
fi

printf 'Host config: %s\n' "$HOST_CONFIG_DIR"
printf 'Example: %s\n' "$example_dir"
