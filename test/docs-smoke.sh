#!/usr/bin/env bash
# Focused smoke test for the documentation after the OpenSpec migration:
# README.md, NOTICE, and the migration note must describe OpenSpec and carry no
# vendored Superpowers runtime.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
cd "$REPO"

fail=0
pass() { printf 'PASS %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*" >&2; fail=1; }

contains() {
  local path="$1" needle="$2" label="$3"
  if grep -qF -- "$needle" "$path"; then
    pass "$label"
  else
    bad "$label (missing '$needle' in $path)"
  fi
}

absent() {
  local path="$1" needle="$2" label="$3"
  if grep -qF -- "$needle" "$path"; then
    bad "$label (found '$needle' in $path)"
  else
    pass "$label"
  fi
}

readme="README.md"
if [ ! -f "$readme" ]; then
  bad "README.md exists"
  echo "DOCS SMOKE FAILED" >&2
  exit 1
fi
pass "README.md exists"

# 1. The README describes the OpenSpec flow and the pinned version.
for needle in 'openspec init' 'OpenSpec 2.1.1' 'openspec archive' '22.20'; do
  contains "$readme" "$needle" "README.md contains $needle"
done
contains "$readme" \
  'openspec init --tools opencode --scope project --profile core' \
  "README.md contains the full openspec init command"

# 2. The vendored Superpowers runtime is gone from the README.
for needle in \
  'superpowers.lock' \
  'superpowers-local.patch' \
  'update-superpowers.sh' \
  'Vendored Superpowers'; do
  absent "$readme" "$needle" "README.md does not contain $needle"
done

# 3. The README path table names the OpenSpec roots.
if grep -qF '| `openspec/` |' "$readme"; then
  pass "README.md path table names openspec/"
else
  bad "README.md path table names openspec/"
fi
if grep -qF '| `.agents/skills/` |' "$readme"; then
  pass "README.md path table names .agents/skills/"
else
  bad "README.md path table names .agents/skills/"
fi

# 4. NOTICE attributes OpenSpec and no longer attributes Superpowers.
notice="NOTICE"
if [ ! -f "$notice" ]; then
  bad "NOTICE exists"
else
  pass "NOTICE exists"
  contains "$notice" 'OpenSpec' "NOTICE attributes OpenSpec"
  contains "$notice" 'Copyright (c) 2025 FISSION AI INC' \
    "NOTICE uses the upstream OpenSpec copyright line"
  absent "$notice" 'Superpowers' "NOTICE does not attribute Superpowers"
fi

# 5. The migration note exists and documents initialization and rollback.
migration="docs/migrations/2026-11-20-openspec.md"
if [ ! -f "$migration" ]; then
  bad "migration note exists ($migration missing)"
else
  pass "migration note exists"
  contains "$migration" 'openspec init' "migration note names openspec init"
  contains "$migration" '2.1.1' "migration note names OpenSpec 2.1.1"
  contains "$migration" '22.20' "migration note names Node.js 22.20"
  if grep -qiE 'rollback' "$migration" &&
     grep -qiE 'restore (the )?previous commit|revert' "$migration"; then
    pass "migration note documents rollback"
  else
    bad "migration note documents rollback"
  fi
  rollback_section="$(sed -n '/^## Rollback$/,$p' "$migration")"
  if printf '%s\n' "$rollback_section" |
     grep -qF -e '902f90c' -e 'before step 1'; then
    pass "migration rollback names the pre-migration commit or before step 1"
  else
    bad "migration rollback names the pre-migration commit or before step 1"
  fi
fi

# 6. Every README path-table entry that the static suite requires exists.
#    research/ and repos/ are gitignored runtime directories created outside a
#    fresh clone, so the table names them but the static suite does not require
#    them.
missing=0
while IFS= read -r path; do
  case "$path" in
    research/ | repos/) continue ;;
  esac
  if [ -e "$path" ]; then
    pass "README path-table entry exists: $path"
  else
    bad "README path-table entry exists ($path missing)"
    missing=1
  fi
done < <(sed -n '/^### Files$/,/^### /p' "$readme" |
  sed -n 's/^| `\([^`]*\)` |.*$/\1/p')
if [ "$missing" -eq 0 ]; then
  pass "README path-table entries required by the static suite exist"
fi

if [ "$fail" -ne 0 ]; then
  echo "DOCS SMOKE FAILED" >&2
  exit 1
fi
echo "DOCS SMOKE PASSED"
