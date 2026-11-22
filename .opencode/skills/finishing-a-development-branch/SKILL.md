---
name: finishing-a-development-branch
description: Use when a development branch is ready to hand off, to verify tests and review, write the commit message, obtain explicit approval before merge or push, and clean up.
---

# Finishing a Development Branch

## Overview

Finish a branch with evidence, not optimism. Confirm the tests and review are
current, write an accurate commit message, get explicit user approval before
merge or push, and clean up only what was approved.

**Never push or merge without explicit user approval.** Do not treat a general
request to "finish" as approval to publish.

## Checklist

### 1. Tests

- Run the project's canonical full-suite command on the final tree.
- Record the command and the output, including any failure.
- Re-run any focused test named in the branch's task reports.
- Confirm `git status` shows only intended changes.

### 2. Review

- Confirm every task report has RED and GREEN evidence.
- Confirm the validator returned PASS against this tree, with commands in its
  report.
- Confirm the security-reviewer verdict, or that its findings are fixed and
  re-reviewed.
- Resolve every open review finding or report it as residual risk.

### 3. Commit message

Write a message that states the behavior change and why it is needed:

```text
<type>(<scope>): <imperative summary>

<body: the problem, the change, and the observable result>

<trailers: task, change, or review references>
```

Match the repository's existing convention. Do not claim tests or review in the
message unless the evidence exists. Stage only intended files; inspect
`git diff --staged` before committing.

### 4. Approval and publish

- Report the exact merge or push commands you propose.
- Wait for explicit user approval for that exact scope.
- On approval, run the commands and report the result, including the remote and
  branch.
- If approval is absent or narrower than the proposed action, stop and ask.

Never force-push, rewrite history, or merge on your own initiative.

### 5. Cleanup

- After merge or push, remove any worktree created for the branch only when the
  user approved it, using `using-git-worktrees` rules.
- Delete the local branch only with explicit approval.
- Leave the main checkout on the branch the user expects, and report it.
- Report any discarded work, the final branch state, and remaining follow-ups.

## Final report

Return the branch, the commit, the test summary, the validator and
security-reviewer verdicts, the approval you received, the commands run, and
any residual risk.
