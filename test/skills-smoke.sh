#!/usr/bin/env bash
# Focused smoke test for the native process skills and the OpenSpec-aware
# orchestration skill.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
cd "$REPO"

fail=0
pass() { printf 'PASS %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*" >&2; fail=1; }

native_skills=(
  test-driven-development
  systematic-debugging
  verification-before-completion
  receiving-code-review
  using-git-worktrees
  finishing-a-development-branch
)

# 1. Every native skill exists with frontmatter name and a "Use when" description.
for skill in "${native_skills[@]}"; do
  path=".opencode/skills/$skill/SKILL.md"
  if [ ! -f "$path" ]; then
    bad "skill $skill exists ($path missing)"
    continue
  fi
  pass "skill $skill exists"
  if grep -qx "name: $skill" "$path"; then
    pass "skill $skill name matches its directory"
  else
    bad "skill $skill name matches its directory"
  fi
  if grep -qE '^description: Use when ' "$path"; then
    pass "skill $skill description starts with 'Use when '"
  else
    bad "skill $skill description starts with 'Use when '"
  fi
done

# 2. The orchestration skill points at the OpenSpec artifact tree and states the
#    advisory boundary.
orchestration=".opencode/skills/orchestration/SKILL.md"
if [ ! -f "$orchestration" ]; then
  bad "orchestration skill exists ($orchestration missing)"
else
  pass "orchestration skill exists"
  if grep -qF 'openspec/changes/' "$orchestration"; then
    pass "orchestration names openspec/changes/"
  else
    bad "orchestration names openspec/changes/"
  fi
  if grep -qF 'openspec/specs/' "$orchestration"; then
    pass "orchestration names openspec/specs/"
  else
    bad "orchestration names openspec/specs/"
  fi
  if grep -qiE 'openspec (verify|verification) is advisory' "$orchestration"; then
    pass "orchestration says OpenSpec verify is advisory"
  else
    bad "orchestration says OpenSpec verify is advisory"
  fi
fi

# 3. The planning step does not present `openspec propose` as a shell command.
#    It points at the generated skill or the real CLI commands instead.
if grep -qF 'openspec propose' "$orchestration"; then
  bad "orchestration does not present openspec propose as a shell command"
else
  pass "orchestration does not present openspec propose as a shell command"
fi
if grep -qF '/openspec-propose' "$orchestration" ||
   grep -qF 'openspec new change' "$orchestration"; then
  pass "orchestration points at the propose skill or the CLI commands"
else
  bad "orchestration points at the propose skill or the CLI commands"
fi

# 4. The removed Superpowers planning references are gone.
for removed in brainstorming writing-plans subagent-driven-development; do
  if grep -qF "$removed" "$orchestration" 2>/dev/null; then
    bad "orchestration no longer references $removed"
  else
    pass "orchestration no longer references $removed"
  fi
done

# 5. The agent files still name the exact skill IDs they may load.
declare -A allowed=(
  [implementer]="test-driven-development systematic-debugging verification-before-completion receiving-code-review"
  [validator]="code-review verification-before-completion"
)
for agent in implementer validator; do
  path=".opencode/agents/$agent.md"
  if [ ! -f "$path" ]; then
    bad "agent $agent exists ($path missing)"
    continue
  fi
  for skill in ${allowed[$agent]}; do
    if grep -qE "^[[:space:]]*resource: \"?$skill\"?[[:space:]]*$" "$path"; then
      pass "agent $agent allows skill $skill"
    else
      bad "agent $agent allows skill $skill"
    fi
  done
done

# 6. Native skills ship as Markdown only, with no scripts directory.
for skill in "${native_skills[@]}"; do
  dir=".opencode/skills/$skill"
  [ -d "$dir" ] || continue
  if [ -n "$(find "$dir" -type d -name scripts -print -quit)" ]; then
    bad "skill $skill contains no scripts/ directory"
  else
    pass "skill $skill contains no scripts/ directory"
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "SKILLS SMOKE FAILED" >&2
  exit 1
fi
echo "SKILLS SMOKE PASSED"
