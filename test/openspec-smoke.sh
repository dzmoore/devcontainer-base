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

# 7. post-create.sh enforces the toolchain versions OpenSpec 2.1.1 requires.
extract_function() {
  local name="$1"
  awk -v fn="$name" '
    $0 ~ ("^" fn "\\(\\) \\{") { capture = 1 }
    capture { print }
    capture && $0 == "}" { exit }
  ' "$post_create"
}

version_ge_src="$(extract_function version_ge)"
node_guard_src="$(extract_function require_node_version)"
openspec_guard_src="$(extract_function require_openspec_version)"

if [ -z "$version_ge_src" ] || [ -z "$node_guard_src" ]; then
  bad "post-create.sh defines a Node.js version guard"
elif ! (
  eval "$version_ge_src"
  eval "$node_guard_src"
  node() { printf 'v22.19.9\n'; }
  if require_node_version >/dev/null 2>&1; then exit 1; fi
  node() { printf 'v22.20.0\n'; }
  require_node_version >/dev/null 2>&1 || exit 1
  node() { printf 'v26.13.1\n'; }
  require_node_version >/dev/null 2>&1 || exit 1
); then
  bad "post-create.sh rejects Node.js below 22.20.0"
else
  pass "post-create.sh rejects Node.js below 22.20.0"
fi

node_guard_calls="$(grep -cE '^[^#]*require_node_version' "$post_create" || true)"
if [ "$node_guard_calls" -ge 2 ]; then
  pass "post-create.sh invokes the Node.js version guard"
else
  bad "post-create.sh invokes the Node.js version guard (found $node_guard_calls references)"
fi

if [ -z "$openspec_guard_src" ]; then
  bad "post-create.sh defines an OpenSpec version assertion"
elif ! (
  eval "$openspec_guard_src"
  openspec() { printf '2.0.0\n'; }
  if require_openspec_version >/dev/null 2>&1; then exit 1; fi
  openspec() { printf '2.1.1\n'; }
  require_openspec_version >/dev/null 2>&1 || exit 1
  openspec() { printf 'openspec 2.1.1\n'; }
  require_openspec_version >/dev/null 2>&1 || exit 1
  openspec() { printf '2.1.10\n'; }
  if require_openspec_version >/dev/null 2>&1; then exit 1; fi
); then
  bad "post-create.sh rejects an OpenSpec version other than 2.1.1"
else
  pass "post-create.sh rejects an OpenSpec version other than 2.1.1"
fi

openspec_guard_calls="$(grep -cE '^[^#]*require_openspec_version' "$post_create" || true)"
if [ "$openspec_guard_calls" -ge 2 ]; then
  pass "post-create.sh invokes the OpenSpec version assertion"
else
  bad "post-create.sh invokes the OpenSpec version assertion (found $openspec_guard_calls references)"
fi

if [ "$fail" -ne 0 ]; then
  echo "OPENSPEC SMOKE FAILED" >&2
  exit 1
fi
echo "OPENSPEC SMOKE PASSED"
