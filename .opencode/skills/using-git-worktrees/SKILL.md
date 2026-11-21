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

- Resolve the target with `readlink -f` and reject a symlink target.
- Reject a path that is not under `/workspace/repos/.worktrees/` and does not
  resolve inside the repository's worktree root.
- Use a plain name of letters, digits, dots, underscores, and hyphens. Reject
  slashes, spaces, and `..`.
- Confirm the branch is not already checked out in another worktree.
- Never run `git reset --hard`, delete uncommitted work, or remove a worktree
  with changes unless the user explicitly approved it.

## Create

```bash
root=/workspace/repos/.worktrees/<owner>/<repo>
name=<name>
target="$root/$name"

case "$name" in
  *[!A-Za-z0-9._-]*|'') echo "invalid worktree name: $name" >&2; exit 1 ;;
esac
mkdir -p "$root"
[ ! -L "$target" ] || { echo "symlink worktree: $target" >&2; exit 1; }

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
git worktree remove <path>
```

Removal refuses a dirty worktree. If the user explicitly approved discarding
the work, use `git worktree remove --force <path>` and say so in the report.
Then run `git worktree prune` to clear stale metadata.

## Cleanup rules

- Remove a worktree when its branch is merged, pushed, or abandoned and the
  user has approved the cleanup.
- Keep the branch unless the user approved deleting it.
- Report the removed path, the branch state, and any work that was discarded.
- Never remove the main checkout, a path outside the worktree root, or a path
  that resolves through a symlink.
