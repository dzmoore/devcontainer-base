#!/usr/bin/env bash
# Render Excalidraw sources to PNG files beside them.
#
# Usage:
#   scripts/render-excalidraw.sh <source.excalidraw> [...]
#
# The .excalidraw file is the source; the .png is derived. The script uses the
# official Excalidraw CLI through the headless Firefox ESR installed in the
# devcontainer. The first run downloads the pinned CLI; later runs use the npm
# cache.
set -euo pipefail

RENDERER_VERSION="0.3.0"
SCALE="2"
BROWSER_PATH="${EXCALIDRAW_BROWSER_PATH:-/usr/bin/firefox-esr}"

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
  args=(render "$input" --out "$output" --scale "$SCALE")
  if [ -x "$BROWSER_PATH" ]; then
    args+=(--browser-path "$BROWSER_PATH")
  fi
  npx --yes "@excalidraw/cli@$RENDERER_VERSION" "${args[@]}"
  [ -s "$output" ] || {
    printf 'error: render produced no PNG: %s\n' "$output" >&2
    exit 1
  }
done
