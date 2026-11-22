---
name: receiving-code-review
description: Use when the orchestrator forwards review findings or a validator returns FAIL, to triage each finding, verify it against the code, fix or rebut with evidence, re-run checks, and report the disposition.
---

# Receiving Code Review

## Overview

Treat each review finding as a hypothesis to verify, not an instruction to
obey and not a criticism to dismiss. Check it against the code, decide with
evidence, make the fix if it is real, and report what you did with each item.

## Triage

For each finding:

1. **Restate it.** Name the file, line, behavior, and the reviewer's proposed
   risk in one sentence.
2. **Check it against the current code.** Read the relevant lines and run the
   smallest command that shows the behavior. The reviewer may be looking at an
   older revision or missing context.
3. **Classify it:** real defect, real improvement, already handled, incorrect,
   or out of scope for this task.
4. **Decide:** fix, rebut with evidence, or escalate to the orchestrator.

## Fix

- For a behavior defect, follow `test-driven-development`: write a failing test
  that reproduces the finding, watch it fail, then fix it.
- Make the smallest fix that resolves the finding. Do not fold in unrelated
  refactoring.
- Re-run the focused test, the reviewer's command if one was given, and the
  project's full suite.

## Rebut

A rebuttal needs evidence, not preference. Cite the code path, the test, the
documented requirement, or the command output that shows the finding is already
handled or incorrect. State the residual risk if the reviewer may still be
right about a case you cannot test.

## Report the disposition

Return one entry per finding with:

```text
Finding: <short title>
Location: <file:line>
Status: fixed | rebutted | already handled | out of scope
Evidence: <command and output, or code reference>
Follow-up: <none, or the separate change that should own it>
```

Then report the focused and full-suite results after the fixes, and list any
finding still open. Do not silently drop a finding, and do not claim a fix
without a command result that shows it.
