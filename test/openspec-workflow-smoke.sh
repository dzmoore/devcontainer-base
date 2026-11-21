#!/usr/bin/env bash
# End-to-end smoke test for the OpenSpec workflow in a disposable repository.
#
# Proves the full path the control plane depends on: initialize a project,
# create a change, write the four artifacts, validate strictly, archive the
# change, and confirm the living spec was updated. Everything happens under
# /tmp/opencode so the repository tree is never touched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
WORK_ROOT="/tmp/opencode/openspec-workflow-$$"
CHANGE="sample-change"
CAPABILITY="sample"

fail=0
pass() { printf 'PASS %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*" >&2; fail=1; }

cleanup() {
  rm -rf -- "$WORK_ROOT"
}
trap cleanup EXIT INT TERM

if ! command -v openspec >/dev/null 2>&1; then
  echo "FAIL: openspec not found on PATH" >&2
  echo "OPENSPEC WORKFLOW SMOKE FAILED" >&2
  exit 1
fi
pass "openspec is on PATH"

if ! command -v git >/dev/null 2>&1; then
  echo "FAIL: git not found on PATH" >&2
  echo "OPENSPEC WORKFLOW SMOKE FAILED" >&2
  exit 1
fi

mkdir -p /tmp/opencode
rm -rf -- "$WORK_ROOT"
mkdir -p "$WORK_ROOT"
cd "$WORK_ROOT"

git init -q .
git config user.name "OpenSpec Workflow Smoke"
git config user.email "smoke@example.invalid"
pass "created disposable repository at $WORK_ROOT"

if ! init_output="$(openspec init --tools opencode --scope project --profile core --no-animation 2>&1)"; then
  printf '%s\n' "$init_output" >&2
  bad "openspec init --tools opencode --scope project --profile core --no-animation"
  echo "OPENSPEC WORKFLOW SMOKE FAILED" >&2
  exit 1
fi
pass "openspec init"

if ! new_output="$(openspec new change "$CHANGE" 2>&1)"; then
  printf '%s\n' "$new_output" >&2
  bad "openspec new change $CHANGE"
  echo "OPENSPEC WORKFLOW SMOKE FAILED" >&2
  exit 1
fi
pass "openspec new change $CHANGE"

mkdir -p "openspec/changes/$CHANGE/specs/$CAPABILITY"
cat >"openspec/changes/$CHANGE/proposal.md" <<'EOF'
# Proposal

## Why

Prove the OpenSpec workflow works end to end in a disposable repository.

## What Changes

- Add a `sample` capability with one requirement.

## Capabilities

### New Capabilities

- `sample`: a minimal capability used by the workflow smoke test.

### Modified Capabilities

None.

## Impact

None outside the disposable repository.
EOF

cat >"openspec/changes/$CHANGE/specs/$CAPABILITY/spec.md" <<'EOF'
# Spec Delta

## Purpose

Define one minimal requirement for the workflow smoke test.

## ADDED Requirements

### Requirement: Sample capability reports readiness
The sample capability SHALL report readiness when invoked.

#### Scenario: Readiness is reported
- **WHEN** the sample capability is invoked
- **THEN** it reports readiness.
EOF

cat >"openspec/changes/$CHANGE/design.md" <<'EOF'
# Design

The smoke test uses one capability and one requirement so the archive step can
fold a single delta into the living spec without ambiguity.
EOF

cat >"openspec/changes/$CHANGE/tasks.md" <<'EOF'
# Tasks

## 1. Implement the sample capability

- [x] 1.1 Add the sample requirement and verify the living spec after archive.
EOF
pass "wrote proposal, delta spec, design, and tasks"

if ! validate_output="$(openspec validate "$CHANGE" --strict 2>&1)"; then
  printf '%s\n' "$validate_output" >&2
  bad "openspec validate $CHANGE --strict"
  echo "OPENSPEC WORKFLOW SMOKE FAILED" >&2
  exit 1
fi
pass "openspec validate $CHANGE --strict"

if ! archive_output="$(openspec archive "$CHANGE" -y 2>&1)"; then
  printf '%s\n' "$archive_output" >&2
  bad "openspec archive $CHANGE -y"
  echo "OPENSPEC WORKFLOW SMOKE FAILED" >&2
  exit 1
fi
pass "openspec archive $CHANGE -y"

living="openspec/specs/$CAPABILITY/spec.md"
if [ -f "$living" ]; then
  pass "living spec exists at $living"
else
  bad "living spec exists at $living"
fi
if [ -f "$living" ] && grep -qF 'Sample capability reports readiness' "$living"; then
  pass "living spec contains the archived requirement"
else
  bad "living spec contains the archived requirement"
fi

archived_dir="$(find openspec/changes/archive -mindepth 1 -maxdepth 1 -type d \
  -name "*-$CHANGE" -print -quit 2>/dev/null || true)"
if [ -n "$archived_dir" ] && [ -d "$archived_dir" ]; then
  pass "change archived under $archived_dir"
else
  bad "change archived under openspec/changes/archive/*-$CHANGE"
fi
if [ -d "openspec/changes/$CHANGE" ]; then
  bad "active change directory removed after archive"
else
  pass "active change directory removed after archive"
fi

if [ "$fail" -ne 0 ]; then
  echo "OPENSPEC WORKFLOW SMOKE FAILED" >&2
  exit 1
fi
echo "OPENSPEC WORKFLOW SMOKE PASSED"
