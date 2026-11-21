#!/usr/bin/env bash
# Focused smoke test for the control-plane instructions and agent prompts after
# the OpenSpec migration: no stale Superpowers references, OpenSpec artifacts in
# the right roles, and unchanged lifecycle permissions.
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

agents=".opencode/AGENTS.md"
if [ ! -f "$agents" ]; then
  bad "AGENTS.md exists ($agents missing)"
  echo "AGENTS SMOKE FAILED" >&2
  exit 1
fi
pass "AGENTS.md exists"

# 1. No stale Superpowers bootstrap or planning references.
for removed in \
  'Superpowers' \
  'superpowers:' \
  'using-superpowers' \
  'brainstorming' \
  'writing-plans' \
  'subagent-driven-development'; do
  absent "$agents" "$removed" "AGENTS.md no longer references $removed"
done

# 2. The OpenSpec workflow and the deny-all plugin posture are documented.
contains "$agents" 'openspec/changes/' "AGENTS.md names openspec/changes/"
contains "$agents" 'openspec/specs/' "AGENTS.md names openspec/specs/"
contains "$agents" 'openspec init' "AGENTS.md names openspec init"
contains "$agents" 'plugin.use *' "AGENTS.md names the plugin.use * policy"
if grep -qE 'deny.*plugin\.use \*|plugin\.use \*.*deny' "$agents"; then
  pass "AGENTS.md states the plugin.use * deny posture"
else
  bad "AGENTS.md states the plugin.use * deny posture"
fi

# 2b. The advisory verification sentence names the real CLI command.
contains "$agents" \
  'OpenSpec verification (run `openspec validate <change> --strict`) is advisory' \
  "AGENTS.md names openspec validate in the advisory sentence"
absent "$agents" 'OpenSpec `verify` is advisory' \
  "AGENTS.md does not present openspec verify as a command"

# 3. The orchestrator prompt drops the plugin bootstrap and owns openspec/**.
orchestrator=".opencode/agents/orchestrator.md"
if [ ! -f "$orchestrator" ]; then
  bad "orchestrator.md exists ($orchestrator missing)"
else
  pass "orchestrator.md exists"
  absent "$orchestrator" 'Superpowers plugin injects' \
    "orchestrator.md no longer mentions the Superpowers plugin bootstrap"
  contains "$orchestrator" 'orchestration' \
    "orchestrator.md names the orchestration skill"
  contains "$orchestrator" 'using-git-worktrees' \
    "orchestrator.md names the using-git-worktrees skill"
  contains "$orchestrator" '**/openspec/**' \
    "orchestrator.md allows edit on **/openspec/**"
  absent "$orchestrator" '**/docs/superpowers/**' \
    "orchestrator.md no longer allows edit on **/docs/superpowers/**"
fi

# 4. Each worker names the OpenSpec change artifacts its role needs.
declare -A artifacts=(
  [task-enumerator]='openspec/changes/ proposal.md design.md tasks.md'
  [design]='openspec/changes/ proposal.md design.md'
  [rubber-duck]='openspec/changes/ proposal.md design.md tasks.md'
  [implementer]='openspec/changes/ tasks.md'
  [validator]='openspec/changes/ tasks.md'
)
for agent in task-enumerator design rubber-duck implementer validator; do
  path=".opencode/agents/$agent.md"
  if [ ! -f "$path" ]; then
    bad "agent $agent exists ($path missing)"
    continue
  fi
  pass "agent $agent exists"
  for needle in ${artifacts[$agent]}; do
    contains "$path" "$needle" "agent $agent references $needle"
  done
done

# 5. The implementer and validator still name the exact native skill IDs.
declare -A skills=(
  [implementer]='test-driven-development systematic-debugging verification-before-completion receiving-code-review'
  [validator]='code-review verification-before-completion'
)
for agent in implementer validator; do
  path=".opencode/agents/$agent.md"
  for skill in ${skills[$agent]}; do
    contains "$path" "$skill" "agent $agent names skill $skill"
  done
done

# 6. The static devcontainer contract expects the new orchestrator allow.
devcontainer="test/devcontainer-smoke.sh"
contains "$devcontainer" '**/openspec/**' \
  "devcontainer-smoke expects **/openspec/**"
absent "$devcontainer" '**/docs/superpowers/**' \
  "devcontainer-smoke no longer expects **/docs/superpowers/**"

if [ "$fail" -ne 0 ]; then
  echo "AGENTS SMOKE FAILED" >&2
  exit 1
fi
echo "AGENTS SMOKE PASSED"
