---
name: code-review
description: Use when a validator must check a task or branch against its acceptance criteria, test evidence, red-green proof, and diff, and return an evidence-backed PASS or FAIL verdict without editing files.
---

# Code review

## Overview

A review is a verdict backed by evidence, not a reading of the diff. You check
that the change does what its brief says, that a real test proves it, and that
nothing unrelated moved. You do not edit files. You return PASS or FAIL to the
orchestrator.

## Inputs

Ask the orchestrator for anything missing before you start. You need:

- the task brief or acceptance criteria;
- the diff or the commit range;
- the RED and GREEN command output the implementer reported;
- the project's test and verification commands;
- the document that should change with the behavior, when the gate applies.

If the report has no RED evidence, that is a finding. Do not fill the gap
yourself with a manual test.

## Checks

### Acceptance criteria

Read each criterion and find the code and test that satisfy it. Mark it met,
partially met, or not met. A criterion satisfied only by prose is not met.

### Test evidence

- Does a test exist for the new behavior?
- Does the test fail for the intended reason before the change? Read the RED
  output; if the failure is a missing import, a syntax error, or a wrong path,
  the red step did not prove the behavior.
- Does the same command pass after the change? Rerun it yourself.
- Does the full suite pass? Rerun it, or confirm the exact recorded run against
  the same tree.
- Are the tests deterministic and independent of network, clock, or ordering
  unless the brief allows it?

### Diff review

- **Scope.** Only the files the brief names, plus justified adjacent changes.
- **Correctness.** Edge cases, error handling, empty input, partial failure.
- **Consistency.** Matches the surrounding naming, structure, and patterns.
- **Duplication and dead code.** New code is reachable and used.
- **Generated and vendored files.** Not hand-edited unless the task says so.
- **Permissions and config.** The change does not widen access silently.
- **Secrets.** No credential, token, key, or private URL enters the diff.
- **Documentation gate.** A behavior, command, path, permission, or policy change
  has a matching document change.

### Evidence hygiene

Run the commands yourself and quote the output. If a test needs a container or a
service, say whether it ran and what it required. "Should pass" is not a result.

## Verdict

Return one verdict:

- **PASS** — every acceptance criterion is met, the red-green evidence proves
  the behavior, the full suite passes, and no Blocker or Major finding remains.
- **FAIL** — anything above is false. Name the exact failing criterion or check.

Order findings by severity: Blocker, Major, Minor. Include a finding id, the
location, the evidence, and the smallest fix.

## Report format

```text
Verdict: PASS|FAIL

Acceptance criteria:
  <criterion> — met|partially met|not met — <evidence>

Test evidence:
  RED: <command> — <observed failure>
  GREEN: <command> — <observed result>
  Full suite: <command> — <observed result>

Findings:
  [<severity>] <id> <title>
  Where: <file:line>
  Evidence: <what you observed>
  Fix: <smallest change>

Documentation gate: <closed, not applicable, or the missing document>

Residual risk: <what the tests and review cannot prove>
```

## Boundaries

Do not edit files, fix the finding yourself, ask the user, or launch subagents.
Report to the orchestrator. If a finding needs a code change, return FAIL with
the fix and let the orchestrator dispatch the implementer.

## Common mistakes

- **Reviewing the summary instead of the diff.** Read the change.
- **Trusting the reported test output.** Rerun it.
- **Accepting a red step that failed for the wrong reason.** The failure must
  prove the behavior is absent.
- **Missing the documentation gate.** A stale document is a finding.
- **PASS with an open Blocker.** The verdict is FAIL.
- **Fixing the code in the review.** That destroys the independent check.
