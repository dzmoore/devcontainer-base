#!/usr/bin/env bash
# Refresh or verify the vendored Superpowers plugin.
#
# Usage:
#   scripts/update-superpowers.sh          Refresh the vendored tree.
#   scripts/update-superpowers.sh --check  Verify the working tree and patch.
#
# The script needs network access. It is a maintainer tool; post-create and the
# smoke suite never call it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/.opencode/superpowers"
REPO="https://github.com/obra/superpowers"
REF="v7.0.2"
COMMIT="c62ffea8267a70de07583e153544d355b6748a56"
# c62ffea is the annotated v7.0.2 tag object. Pin the commit it peels to so a
# retagged or moved tag cannot silently change the vendored tree.
RESOLVED_COMMIT="22f0b463e7a5e579904dd6211a520321035526f7"
PATCH="$ROOT/.opencode/superpowers-local.patch"
LOCK="$ROOT/.opencode/superpowers.lock"
MODE="${1:-update}"
[ "$MODE" = "update" ] || [ "$MODE" = "--check" ] || { echo "usage: $0 [--check]" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone --quiet "$REPO" "$tmp/superpowers"
git -C "$tmp/superpowers" checkout --quiet "$COMMIT"

actual_commit="$(git -C "$tmp/superpowers" rev-parse HEAD)"
if [ "$actual_commit" != "$RESOLVED_COMMIT" ]; then
  echo "error: $REF resolved to $actual_commit, expected $RESOLVED_COMMIT" >&2
  exit 1
fi

if ! git -C "$tmp/superpowers" apply --3way "$PATCH"; then
  echo "error: local patch does not apply to $REF" >&2
  exit 1
fi

PATHS=(index.js .opencode/plugins/superpowers.js skills package.json LICENSE)

tree_hash() {
  local dir="$1"
  (
    cd "$dir"
    find . -type f ! -name UPSTREAM.md ! -name superpowers.lock -print0 \
      | LC_ALL=C sort -z \
      | xargs -0 -r sha256sum \
      | LC_ALL=C sort -k2 \
      | sha256sum \
      | awk '{print $1}'
  )
}

patch_hash() {
  sha256sum "$PATCH" | awk '{print $1}'
}

write_upstream() {
  cat >"$DEST/UPSTREAM.md" <<EOF
# Superpowers

- Source: $REPO
- Release: $REF
- Pinned ref: $COMMIT (annotated tag; commit $RESOLVED_COMMIT)
- License: MIT
- Copyright (c) 2025 Jesse Vincent

This tree vendors index.js, .opencode/plugins/superpowers.js, skills/,
package.json, and LICENSE from the pinned upstream release.

## Local patch

../superpowers-local.patch applies to the pinned tree. scripts/update-superpowers.sh
applies it before the tree is copied. It:

- adds canonical TDD references and requires explicit user approval for TDD
  exceptions; and
- maps the subagent-driven-development templates to the named implementer and
  validator agents, removes per-dispatch model selection, and states that agent
  files own model selection; and
- maps the injected V1 and V2 tool guidance, the code-review and parallel
  dispatch skills, and the brainstorming builder check to named control-plane
  agents, and forbids dispatching general.

Verify the tree with scripts/update-superpowers.sh --check.
EOF
}

if [ "$MODE" = "update" ]; then
  rm -rf "$DEST"
  mkdir -p "$DEST/.opencode/plugins"
  cp "$tmp/superpowers/index.js" "$DEST/index.js"
  cp "$tmp/superpowers/.opencode/plugins/superpowers.js" "$DEST/.opencode/plugins/superpowers.js"
  cp -R "$tmp/superpowers/skills" "$DEST/skills"
  cp "$tmp/superpowers/package.json" "$DEST/package.json"
  cp "$tmp/superpowers/LICENSE" "$DEST/LICENSE"
  write_upstream

  tree="$(tree_hash "$DEST")"
  patch="$(patch_hash)"
  cat >"$LOCK" <<EOF
upstream=$REPO.git
ref=$REF
commit=$COMMIT
resolved_commit=$RESOLVED_COMMIT
tree_sha256=$tree
patch_sha256=$patch
EOF

  printf 'Updated vendored Superpowers to %s (%s).\n' "$REF" "$RESOLVED_COMMIT"
  printf 'Review the diff before committing.\n'
  exit 0
fi

[ -f "$PATCH" ] || { echo "error: $PATCH missing" >&2; exit 1; }
[ -f "$LOCK" ] || { echo "error: $LOCK missing" >&2; exit 1; }
[ -f "$DEST/UPSTREAM.md" ] || { echo "error: $DEST/UPSTREAM.md missing" >&2; exit 1; }
grep -qF "$COMMIT" "$DEST/UPSTREAM.md" \
  || { echo "error: $DEST/UPSTREAM.md does not record $COMMIT" >&2; exit 1; }

drift=0
for rel in "${PATHS[@]}"; do
  src="$tmp/superpowers/$rel"
  dst="$DEST/$rel"
  if [ -d "$src" ]; then
    if ! diff -ru "$dst" "$src"; then
      echo "error: $rel drifted from $REF" >&2
      drift=1
    fi
  elif ! diff -u "$dst" "$src"; then
    echo "error: $rel drifted from $REF" >&2
    drift=1
  fi
done

recorded_patch="$(sed -n 's/^patch_sha256=//p' "$LOCK")"
current_patch="$(patch_hash)"
if [ "$recorded_patch" != "$current_patch" ]; then
  echo "error: superpowers-local.patch hash mismatch (lock $recorded_patch, got $current_patch)" >&2
  drift=1
fi

recorded_tree="$(sed -n 's/^tree_sha256=//p' "$LOCK")"
current_tree="$(tree_hash "$DEST")"
if [ "$recorded_tree" != "$current_tree" ]; then
  echo "error: vendored tree hash mismatch (lock $recorded_tree, got $current_tree)" >&2
  drift=1
fi

[ "$drift" -eq 0 ] || exit 1
printf 'Vendored Superpowers matches %s.\n' "$REF"
