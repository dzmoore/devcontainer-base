#!/usr/bin/env bash
# Render Excalidraw sources to PNG files beside them.
#
# Usage:
#   scripts/render-excalidraw.sh <source.excalidraw> [...]
#
# The .excalidraw file is the source; the .png is derived. The script uses a
# pinned pure-computation renderer, so it needs no browser. The first run
# downloads the package; later runs use the npm cache.
set -euo pipefail

RENDERER_VERSION="0.2.1"
SCALE="2"

usage() {
  printf 'Usage: %s <source.excalidraw> [...]\n' "$0" >&2
  exit 2
}

[ "$#" -gt 0 ] || usage
command -v npx >/dev/null 2>&1 || {
  printf 'error: npx is required to render Excalidraw files\n' >&2
  exit 2
}

for input in "$@"; do
  case "$input" in
    *.excalidraw) ;;
    *)
      printf 'error: expected a .excalidraw file: %s\n' "$input" >&2
      exit 2
      ;;
  esac
  [ -f "$input" ] || {
    printf 'error: source file not found: %s\n' "$input" >&2
    exit 2
  }

  output="${input%.excalidraw}.png"
  npx --yes "@moona3k/excalidraw-export@$RENDERER_VERSION" \
    "$input" -o "$output" --scale "$SCALE"
  [ -s "$output" ] || {
    printf 'error: render produced no PNG: %s\n' "$output" >&2
    exit 1
  }
done
