#!/usr/bin/env bash
# Refresh or verify the vendored writing skills.
#
# Usage:
#   scripts/update-writing-skills.sh          Refresh both vendored trees.
#   scripts/update-writing-skills.sh --check  Verify the working tree matches.
#
# The script needs network access. It is not part of the smoke suite.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-update}"

TW_REPO="https://github.com/riekelt/technical-writer"
TW_SHA="85e53729dd959a2795d593d6769068e342cf3486"
TW_DEST="$ROOT/.opencode/skills/technical-writer"

EOS_REPO="https://github.com/obra/the-elements-of-style"
EOS_SHA="05fc4f0d2b97b7c042dd9949ad658568e4a1324e"
EOS_DEST="$ROOT/.opencode/skills/elements-of-style"

usage() {
  printf 'Usage: %s [--check]\n' "$0" >&2
  exit 2
}

case "$MODE" in
  update|--check) ;;
  *) usage ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

clone_at() {
  local repo="$1" sha="$2" dest="$3"
  git clone --quiet "$repo" "$dest"
  git -C "$dest" checkout --quiet "$sha"
  git -C "$dest" rev-parse HEAD
}

printf 'Fetching technical-writer at %s\n' "$TW_SHA"
clone_at "$TW_REPO" "$TW_SHA" "$tmp/technical-writer"
printf 'Fetching Elements of Style at %s\n' "$EOS_SHA"
clone_at "$EOS_REPO" "$EOS_SHA" "$tmp/elements-of-style"

if [ "$MODE" = "--check" ]; then
  diff -ru --exclude UPSTREAM.md --exclude LICENSE \
    "$TW_DEST" "$tmp/technical-writer/plugins/technical-writer/skills"
  diff -u "$EOS_DEST/writing-clearly-and-concisely/elements-of-style.md" \
    "$tmp/elements-of-style/skills/writing-clearly-and-concisely/elements-of-style.md"
  printf 'Vendored writing skills match their pins.\n'
  exit 0
fi

rm -rf "$TW_DEST"/*/
cp -R "$tmp/technical-writer/plugins/technical-writer/skills/." "$TW_DEST/"
cp "$tmp/technical-writer/LICENSE" "$TW_DEST/LICENSE"
cp "$tmp/elements-of-style/skills/writing-clearly-and-concisely/elements-of-style.md" \
  "$EOS_DEST/writing-clearly-and-concisely/elements-of-style.md"
printf 'Updated vendored writing skills. Review the diff before committing.\n'
