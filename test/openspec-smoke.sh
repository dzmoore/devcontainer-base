#!/usr/bin/env bash
# Focused smoke test for the OpenSpec toolchain and repository initialization.
set -euo pipefail

# The validation below runs the pinned CLI; do not emit telemetry from a test.
export OPENSPEC_TELEMETRY=0
export DO_NOT_TRACK=1

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

# 4. The approved change is either active or archived. After archive, its delta
#    specs live on as the living specs.
change_name="replace-superpowers-with-openspec"
active_dir="openspec/changes/$change_name"
archived_dir="$(find openspec/changes/archive -mindepth 1 -maxdepth 1 -type d \
  -name "*-$change_name" -print -quit 2>/dev/null || true)"
if [ -d "$active_dir" ]; then
  change_dir="$active_dir"
  change_location="active"
elif [ -n "$archived_dir" ] && [ -d "$archived_dir" ]; then
  change_dir="$archived_dir"
  change_location="archived"
else
  change_dir=""
  change_location="missing"
fi

if [ "$change_location" = "missing" ]; then
  bad "approved change exists at $active_dir or openspec/changes/archive/*-$change_name"
else
  pass "approved change exists ($change_location)"
  check_file "$change_dir/proposal.md" "approved change proposal.md exists"
  check_file "$change_dir/design.md" "approved change design.md exists"
  check_file "$change_dir/tasks.md" "approved change tasks.md exists"
  for spec in control-plane-workflow spec-artifacts; do
    if [ "$change_location" = "active" ]; then
      check_file "$change_dir/specs/$spec/spec.md" \
        "approved change spec $spec exists"
    else
      check_file "openspec/specs/$spec/spec.md" \
        "living spec $spec exists after archive"
    fi
  done
fi

# 5. The active change validates strictly; after archive the living specs do.
if ! command -v openspec >/dev/null 2>&1; then
  bad "openspec validate --strict (openspec not found on PATH)"
elif [ "$change_location" = "active" ]; then
  if validate_output="$(openspec validate "$change_name" --strict 2>&1)"; then
    pass "openspec validate $change_name --strict"
  else
    printf '%s\n' "$validate_output" >&2
    bad "openspec validate $change_name --strict"
  fi
elif [ "$change_location" = "archived" ]; then
  if validate_output="$(openspec validate --specs --strict 2>&1)"; then
    pass "openspec validate --specs --strict"
  else
    printf '%s\n' "$validate_output" >&2
    bad "openspec validate --specs --strict"
  fi
else
  bad "openspec validate --strict (approved change not found)"
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

# 8. OpenSpec telemetry is disabled in the container and by the toolchain.
devcontainer_json=".devcontainer/devcontainer.json"
if [ ! -f "$devcontainer_json" ]; then
  bad "$devcontainer_json exists"
elif ! command -v python3 >/dev/null 2>&1; then
  bad "python3 is available to inspect $devcontainer_json"
else
  telemetry_missing="$(python3 - "$devcontainer_json" 2>/dev/null <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    container_env = json.load(handle).get("containerEnv", {})
missing = [
    f"{key}={want}"
    for key, want in (("OPENSPEC_TELEMETRY", "0"), ("DO_NOT_TRACK", "1"))
    if container_env.get(key) != want
]
print(", ".join(missing))
PY
)" || telemetry_missing="invalid-json"
  if [ -z "$telemetry_missing" ]; then
    pass "devcontainer.json disables telemetry in containerEnv"
  else
    bad "devcontainer.json sets OPENSPEC_TELEMETRY=0 and DO_NOT_TRACK=1 (missing: $telemetry_missing)"
  fi
fi

if [ ! -f "$post_create" ]; then
  bad "$post_create exists for the telemetry opt-out"
else
  if grep -qF 'openspec config set telemetry.enabled false' "$post_create"; then
    pass "post-create.sh disables OpenSpec telemetry"
  else
    bad "post-create.sh disables OpenSpec telemetry"
  fi
  if grep -qF 'openspec config get telemetry.enabled' "$post_create"; then
    pass "post-create.sh verifies the telemetry setting"
  else
    bad "post-create.sh verifies the telemetry setting"
  fi
fi

mkdir -p /tmp/opencode
telemetry_root="$(mktemp -d /tmp/opencode/openspec-telemetry.XXXXXX)"
cleanup_telemetry() { rm -rf -- "${telemetry_root:-}"; }
trap cleanup_telemetry EXIT
if (
  export HOME="$telemetry_root/home"
  export XDG_CONFIG_HOME="$telemetry_root/config"
  export XDG_DATA_HOME="$telemetry_root/data"
  mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
  openspec config set telemetry.enabled false >/dev/null 2>&1
  [ "$(openspec config get telemetry.enabled 2>/dev/null || true)" = "false" ]
); then
  pass "openspec config telemetry.enabled false persists in an isolated home"
else
  bad "openspec config telemetry.enabled false persists in an isolated home"
fi

# 9. The disposable workflow test isolates global OpenSpec state and telemetry.
workflow_smoke="test/openspec-workflow-smoke.sh"
if [ ! -f "$workflow_smoke" ]; then
  bad "$workflow_smoke exists"
else
  isolation_missing=""
  for assignment in \
    'export HOME="$WORK_ROOT/home"' \
    'export XDG_CONFIG_HOME="$WORK_ROOT/config"' \
    'export XDG_DATA_HOME="$WORK_ROOT/data"' \
    'export OPENSPEC_TELEMETRY=0' \
    'export DO_NOT_TRACK=1'; do
    grep -qF "$assignment" "$workflow_smoke" || isolation_missing="$isolation_missing [$assignment]"
  done
  mkdir_lines="$(grep -E '^[[:space:]]*mkdir -p ' "$workflow_smoke" || true)"
  for dir_var in HOME XDG_CONFIG_HOME XDG_DATA_HOME; do
    printf '%s\n' "$mkdir_lines" | grep -qF "\"\$$dir_var\"" ||
      isolation_missing="$isolation_missing [mkdir \$$dir_var]"
  done
  if [ -z "$isolation_missing" ]; then
    pass "openspec-workflow-smoke.sh isolates HOME and telemetry state"
  else
    bad "openspec-workflow-smoke.sh isolates HOME and telemetry state (missing:$isolation_missing)"
  fi

  first_openspec_line="$(grep -nE '(^|[[:space:]])openspec[[:space:]]' "$workflow_smoke" |
    head -n1 | cut -d: -f1)"
  last_export_line="$(grep -nE '^[[:space:]]*export[[:space:]]+(HOME|XDG_CONFIG_HOME|XDG_DATA_HOME|OPENSPEC_TELEMETRY|DO_NOT_TRACK)=' "$workflow_smoke" |
    tail -n1 | cut -d: -f1 || true)"
  if [ -n "$last_export_line" ] && [ -n "$first_openspec_line" ] &&
    [ "$last_export_line" -lt "$first_openspec_line" ]; then
    pass "openspec-workflow-smoke.sh isolates the environment before calling openspec"
  else
    bad "openspec-workflow-smoke.sh isolates the environment before calling openspec"
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "OPENSPEC SMOKE FAILED" >&2
  exit 1
fi
echo "OPENSPEC SMOKE PASSED"
