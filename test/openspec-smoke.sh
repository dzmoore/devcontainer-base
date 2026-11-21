#!/usr/bin/env bash
# Focused smoke test for the OpenSpec toolchain and repository initialization.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
cd "$REPO"

fail=0
pass() { printf 'PASS %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*" >&2; fail=1; }

check_file() {
  local path="$1" label="$2"
  if [ -f "$path" ]; then
    pass "$label"
  else
    bad "$label (missing $path)"
  fi
}

# 1. The pinned CLI is on PATH and reports the approved version.
if ! command -v openspec >/dev/null 2>&1; then
  bad "openspec --version is 2.1.1 (openspec not found on PATH)"
else
  version_output="$(openspec --version 2>&1 || true)"
  version="$(printf '%s\n' "$version_output" |
    grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
  if [ "$version" = "2.1.1" ]; then
    pass "openspec --version is 2.1.1"
  else
    bad "openspec --version is 2.1.1 (got '$version_output')"
  fi
fi

# 2. Repository initialization artifacts.
check_file "openspec/config.yaml" "openspec/config.yaml exists"
check_file ".agents/skills/openspec-propose/SKILL.md" \
  ".agents/skills/openspec-propose/SKILL.md exists"

# 3. The six generated OpenSpec skills are present and no plugin file was added.
for skill in \
  openspec-apply-change \
  openspec-archive-change \
  openspec-explore \
  openspec-propose \
  openspec-sync-specs \
  openspec-update-change; do
  check_file ".agents/skills/$skill/SKILL.md" "generated skill $skill exists"
done
skill_count="$({ find .agents/skills -mindepth 2 -maxdepth 2 -name SKILL.md \
  2>/dev/null || true; } | wc -l | tr -d ' ')"
if [ "$skill_count" -eq 6 ]; then
  pass ".agents/skills contains exactly six generated skills"
else
  bad ".agents/skills contains exactly six generated skills (found $skill_count)"
fi
plugin_files="$(find .agents/skills -type f \
  \( -name 'plugin*' -o -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) \
  2>/dev/null || true)"
if [ -z "$plugin_files" ]; then
  pass ".agents/skills contains no plugin file"
else
  bad ".agents/skills contains no plugin file (found: $plugin_files)"
fi

# 4. The approved change was copied from the spike.
check_file "openspec/changes/replace-superpowers-with-openspec/proposal.md" \
  "approved change proposal.md exists"
check_file "openspec/changes/replace-superpowers-with-openspec/design.md" \
  "approved change design.md exists"
check_file "openspec/changes/replace-superpowers-with-openspec/tasks.md" \
  "approved change tasks.md exists"
for spec in control-plane-workflow spec-artifacts; do
  check_file \
    "openspec/changes/replace-superpowers-with-openspec/specs/$spec/spec.md" \
    "approved change spec $spec exists"
done

# 5. The change validates strictly.
if ! command -v openspec >/dev/null 2>&1; then
  bad "openspec validate replace-superpowers-with-openspec --strict (openspec not found on PATH)"
elif validate_output="$(openspec validate replace-superpowers-with-openspec --strict 2>&1)"; then
  pass "openspec validate replace-superpowers-with-openspec --strict"
else
  printf '%s\n' "$validate_output" >&2
  bad "openspec validate replace-superpowers-with-openspec --strict"
fi

# 6. post-create.sh installs the pinned version idempotently.
post_create=".devcontainer/post-create.sh"
if [ ! -f "$post_create" ]; then
  bad "$post_create exists"
else
  if grep -qF '@fission-ai/openspec@2.1.1' "$post_create"; then
    pass "post-create.sh pins @fission-ai/openspec@2.1.1"
  else
    bad "post-create.sh pins @fission-ai/openspec@2.1.1"
  fi
  if grep -qE 'command -v openspec.*|openspec --version' "$post_create"; then
    pass "post-create.sh has an idempotence guard for openspec"
  else
    bad "post-create.sh has an idempotence guard for openspec"
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "OPENSPEC SMOKE FAILED" >&2
  exit 1
fi
echo "OPENSPEC SMOKE PASSED"
