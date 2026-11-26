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

# 3b. Generated skills stay inert: Markdown only, no executable bits, no
#     scripts, and no shell or JavaScript source files.
check_inert_skill_tree() {
  local root="$1" label="$2"
  local executables source_files script_dirs
  executables="$(find "$root" -type f -perm -u+x -print 2>/dev/null || true)"
  if [ -z "$executables" ]; then
    pass "$label contains no executable file"
  else
    bad "$label contains no executable file (found: $executables)"
  fi
  source_files="$(find "$root" -type f \
    \( -name '*.sh' -o -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) \
    -print 2>/dev/null || true)"
  if [ -z "$source_files" ]; then
    pass "$label contains no shell or JavaScript file"
  else
    bad "$label contains no shell or JavaScript file (found: $source_files)"
  fi
  script_dirs="$(find "$root" -type d -name scripts -print 2>/dev/null || true)"
  if [ -z "$script_dirs" ]; then
    pass "$label contains no scripts/ directory"
  else
    bad "$label contains no scripts/ directory (found: $script_dirs)"
  fi
}

check_inert_skill_tree ".agents/skills" ".agents/skills"

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

# 6. post-create.sh does not install OpenSpec: the CLI comes from the image.
post_create=".devcontainer/post-create.sh"
if [ ! -f "$post_create" ]; then
  bad "$post_create exists"
else
  if grep -qF '@fission-ai/openspec' "$post_create"; then
    bad "post-create.sh does not install OpenSpec from npm (found @fission-ai/openspec)"
  else
    pass "post-create.sh does not install OpenSpec from npm"
  fi
  npm_install_pattern='(^|[^[:alnum:]_-])npm[[:space:]]+install([[:space:]]|$)'
  npm_detector_missed=""
  for sample in \
    'npm install -g foo' \
    '/usr/bin/npm install -g foo' \
    './npm install foo'; do
    printf '%s\n' "$sample" | grep -qE "$npm_install_pattern" ||
      npm_detector_missed="$npm_detector_missed [$sample]"
  done
  if printf '%s\n' 'pnpm install foo' | grep -qE "$npm_install_pattern"; then
    npm_detector_missed="$npm_detector_missed [pnpm false positive]"
  fi
  if [ -z "$npm_detector_missed" ]; then
    pass "npm install detector catches path-qualified invocations and ignores pnpm"
  else
    bad "npm install detector catches path-qualified invocations and ignores pnpm (failed:$npm_detector_missed)"
  fi
  npm_install_lines="$(grep -nE "$npm_install_pattern" "$post_create" || true)"
  if [ -z "$npm_install_lines" ]; then
    pass "post-create.sh does not run npm install"
  else
    bad "post-create.sh does not run npm install (found: $npm_install_lines)"
  fi
  if grep -qF 'openspec --version' "$post_create"; then
    pass "post-create.sh verifies the image-provided openspec --version"
  else
    bad "post-create.sh verifies the image-provided openspec --version"
  fi
  if grep -qF 'if [ "$openspec_version" != "2.1.1" ]; then' "$post_create"; then
    pass "post-create.sh fails unless the OpenSpec version is exactly 2.1.1"
  else
    bad "post-create.sh fails unless the OpenSpec version is exactly 2.1.1"
  fi
  if grep -qF 'OpenSpec version mismatch: expected 2.1.1' "$post_create"; then
    pass "post-create.sh reports an explicit OpenSpec mismatch"
  else
    bad "post-create.sh reports an explicit OpenSpec mismatch"
  fi
fi

# 7. post-create.sh no longer carries the deleted Node/OpenSpec shell guards.
if [ ! -f "$post_create" ]; then
  bad "$post_create exists for the guard removal"
else
  for guard in version_ge require_node_version require_openspec_version; do
    if grep -qF "$guard" "$post_create"; then
      bad "post-create.sh does not define or call $guard"
    else
      pass "post-create.sh does not define or call $guard"
    fi
  done
  for node_check in 'command -v node' 'node --version'; do
    if grep -qF "$node_check" "$post_create"; then
      bad "post-create.sh does not check Node ($node_check)"
    else
      pass "post-create.sh does not check Node ($node_check)"
    fi
  done
  if grep -qF 'openspec --version' "$post_create"; then
    pass "post-create.sh keeps the openspec --version verification"
  else
    bad "post-create.sh keeps the openspec --version verification"
  fi
  if grep -qF 'if [ "$openspec_version" != "2.1.1" ]; then' "$post_create"; then
    pass "post-create.sh keeps the strict 2.1.1 verification"
  else
    bad "post-create.sh keeps the strict 2.1.1 verification"
  fi
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
