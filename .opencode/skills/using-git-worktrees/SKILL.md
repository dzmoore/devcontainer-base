---
name: using-git-worktrees
description: Use when work needs an isolated checkout, to create, list, move, and remove git worktrees under /workspace/repos/.worktrees with path and symlink safety checks.
---

# Using Git Worktrees

## Overview

A worktree is a second checkout of one repository, useful for parallel branches
without disturbing the main tree. Keep every worktree under the canonical root
and validate paths before creating or removing anything.

Canonical root: `/workspace/repos/.worktrees/<owner>/<repo>/<name>`

`/worktrees` is a compatibility path for existing scripts. Do not create
worktrees outside the canonical root.

## Safety checks

Before any create or remove:

- Validate the name with the `worktree_name_is_valid` predicate: reject the
  empty name, `.`, `..`, any name containing `..`, any name containing `/`,
  and any character outside `[A-Za-z0-9._-]`.
- Resolve the worktree root with `readlink -f` and fall back to `realpath -m`
  when the root does not exist yet. Resolve the target with `realpath -m`.
- Reject any resolved target that is not under `/workspace/repos/.worktrees/`
  or that escapes the resolved root. Reject a symlink target.
- Apply the same name, containment, and symlink checks before
  `git worktree remove`.
- Confirm the branch is not already checked out in another worktree.
- Never run `git reset --hard`, delete uncommitted work, or remove a worktree
  with changes unless the user explicitly approved it.

### Name validation

```bash
worktree_name_is_valid() {
  case "$1" in
    ''|.|..|*..*|*/*|*[!A-Za-z0-9._-]*)
      return 1
      ;;
  esac
  return 0
}
```

### Path containment

```bash
root=/workspace/repos/.worktrees/<owner>/<repo>
name=<name>
worktree_name_is_valid "$name" || { echo "invalid worktree name: $name" >&2; exit 1; }
resolved_root="$(readlink -f "$root" 2>/dev/null || true)"
[ -n "$resolved_root" ] || resolved_root="$(realpath -m "$root")"
target="$(realpath -m "$resolved_root/$name")"
case "$target" in
  /workspace/repos/.worktrees/*) ;;
  *) echo "worktree outside the worktree root: $target" >&2; exit 1 ;;
esac
case "$target" in
  "$resolved_root"/*) ;;
  *) echo "worktree escapes its repository root: $target" >&2; exit 1 ;;
esac
[ ! -L "$target" ] || { echo "symlink worktree: $target" >&2; exit 1; }
```

## Create

```bash
root=/workspace/repos/.worktrees/<owner>/<repo>
name=<name>
worktree_name_is_valid "$name" || { echo "invalid worktree name: $name" >&2; exit 1; }
resolved_root="$(readlink -f "$root" 2>/dev/null || true)"
[ -n "$resolved_root" ] || resolved_root="$(realpath -m "$root")"
target="$(realpath -m "$resolved_root/$name")"
case "$target" in
  /workspace/repos/.worktrees/*) ;;
  *) echo "worktree outside the worktree root: $target" >&2; exit 1 ;;
esac
[ ! -L "$target" ] || { echo "symlink worktree: $target" >&2; exit 1; }
mkdir -p "$resolved_root"

git worktree add "$target" -b "$name"
```

Use an existing branch instead of `-b` when it already exists. Confirm the new
path with `git worktree list` and report the absolute path.

## List

```bash
git worktree list
git worktree list --porcelain
```

Read the porcelain output when you need to detect a path, branch, or locked
entry programmatically.

## Move

Git has no move subcommand. To relocate a worktree:

1. Confirm the worktree is clean and its branch has no uncommitted work.
2. Remove the old worktree with `git worktree remove <old-path>`.
3. Create it at the new path with `git worktree add <new-path> <branch>`.
4. Confirm `git worktree list` shows only the new path.

Do not `mv` a worktree directory; the repository's administrative metadata
would point at the old path.

## Remove

```bash
root=/workspace/repos/.worktrees/<owner>/<repo>
name=<name>
worktree_name_is_valid "$name" || { echo "invalid worktree name: $name" >&2; exit 1; }
resolved_root="$(readlink -f "$root" 2>/dev/null || true)"
[ -n "$resolved_root" ] || resolved_root="$(realpath -m "$root")"
target="$(realpath -m "$resolved_root/$name")"
case "$target" in
  /workspace/repos/.worktrees/*) ;;
  *) echo "worktree outside the worktree root: $target" >&2; exit 1 ;;
esac
[ ! -L "$target" ] || { echo "symlink worktree: $target" >&2; exit 1; }

git worktree remove "$target"
```

The same name, containment, and symlink checks run before removal. Removal
refuses a dirty worktree. If the user explicitly approved discarding the work,
use `git worktree remove --force "$target"` and say so in the report. Then run
`git worktree prune` to clear stale metadata.

## Cleanup rules

- Remove a worktree when its branch is merged, pushed, or abandoned and the
  user has approved the cleanup.
- Keep the branch unless the user approved deleting it.
- Report the removed path, the branch state, and any work that was discarded.
- Never remove the main checkout, a path outside the worktree root, or a path
  that resolves through a symlink.
