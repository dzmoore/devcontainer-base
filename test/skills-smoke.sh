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

# 6. Native skills ship as Markdown only: no scripts directory, no executable
#    files, and no shell or JavaScript source.
for skill in "${native_skills[@]}"; do
  dir=".opencode/skills/$skill"
  [ -d "$dir" ] || continue
  if [ -n "$(find "$dir" -type d -name scripts -print -quit)" ]; then
    bad "skill $skill contains no scripts/ directory"
  else
    pass "skill $skill contains no scripts/ directory"
  fi
  if [ -n "$(find "$dir" -type f -perm -u+x -print -quit)" ]; then
    bad "skill $skill contains no executable file"
  else
    pass "skill $skill contains no executable file"
  fi
  if [ -n "$(find "$dir" -type f \
    \( -name '*.sh' -o -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) \
    -print -quit)" ]; then
    bad "skill $skill contains no shell or JavaScript file"
  else
    pass "skill $skill contains no shell or JavaScript file"
  fi
done

# 7. The worktree skill rejects unsafe names and keeps every target inside the
#    canonical worktree root, before both add and remove.
worktree_skill=".opencode/skills/using-git-worktrees/SKILL.md"
if [ ! -f "$worktree_skill" ]; then
  bad "using-git-worktrees skill exists ($worktree_skill missing)"
else
  pass "using-git-worktrees skill exists"
  for needle in \
    'readlink -f' \
    'realpath -m' \
    '/workspace/repos/.worktrees/' \
    "''|.|..|*..*|*/*|*[!A-Za-z0-9._-]*)" \
    'git worktree add "$target"' \
    'git worktree remove "$target"'; do
    if grep -qF -- "$needle" "$worktree_skill"; then
      pass "using-git-worktrees contains: $needle"
    else
      bad "using-git-worktrees contains: $needle"
    fi
  done
  name_check_count="$(grep -cF 'worktree_name_is_valid' "$worktree_skill" || true)"
  if [ "$name_check_count" -ge 3 ]; then
    pass "using-git-worktrees applies the name check before add and remove"
  else
    bad "using-git-worktrees applies the name check before add and remove (found $name_check_count references)"
  fi
  containment_count="$(grep -cF 'case "$target" in' "$worktree_skill" || true)"
  if [ "$containment_count" -ge 2 ]; then
    pass "using-git-worktrees applies the containment check before add and remove"
  else
    bad "using-git-worktrees applies the containment check before add and remove (found $containment_count checks)"
  fi
  symlink_count="$(grep -cF '[ ! -L "$target" ]' "$worktree_skill" || true)"
  if [ "$symlink_count" -ge 2 ]; then
    pass "using-git-worktrees rejects a symlink target before add and remove"
  else
    bad "using-git-worktrees rejects a symlink target before add and remove (found $symlink_count checks)"
  fi

  name_check_src="$({
    awk -v fn="worktree_name_is_valid" '
      $0 ~ ("^" fn "\\(\\) \\{") { capture = 1 }
      capture { print }
      capture && $0 == "}" { exit }
    ' "$worktree_skill"
  } || true)"
  if [ -z "$name_check_src" ]; then
    bad "using-git-worktrees defines a worktree_name_is_valid predicate"
  elif ! (
    eval "$name_check_src"
    for bad_name in '' '.' '..' 'a..b' 'a/b' 'a b' 'a:b' 'a*b'; do
      if worktree_name_is_valid "$bad_name"; then exit 1; fi
    done
    for good_name in 'feature-x' 'a.b_c-1' '2026-11-20-fix'; do
      worktree_name_is_valid "$good_name" || exit 1
    done
  ); then
    bad "using-git-worktrees rejects unsafe worktree names"
  else
    pass "using-git-worktrees rejects unsafe worktree names"
  fi
fi

# 8. The ledger keeps a safe change slug and a root under <repo>/.superpowers/sdd/.
if [ ! -f "$orchestration" ]; then
  bad "orchestration skill exists for the ledger rule"
else
  for needle in \
    '^[a-z0-9][a-z0-9._-]*$' \
    'must not contain `..` or `/`' \
    'readlink -f' \
    '<repo>/.superpowers/sdd/'; do
    if grep -qF -- "$needle" "$orchestration"; then
      pass "orchestration ledger rule contains: $needle"
    else
      bad "orchestration ledger rule contains: $needle"
    fi
  done
fi

if [ "$fail" -ne 0 ]; then
  echo "SKILLS SMOKE FAILED" >&2
  exit 1
fi
echo "SKILLS SMOKE PASSED"
