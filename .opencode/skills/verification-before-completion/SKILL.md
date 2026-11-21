---
name: verification-before-completion
description: Use when about to report a task complete, fixed, or passing, to require current command evidence before any success claim.
---

# Verification Before Completion

## Overview

A claim of completion is a claim about the current tree. Verify it now. Run the
command, read the output, and only then make the claim.

**Rule:** no completion claim without current evidence. A memory of an earlier
run, a worker's summary, or "it should pass" is not evidence.

## Evidence checklist

Before you report done:

- [ ] **Acceptance criteria:** each one has a passing test, a checked command,
      or a documented exception approved by the user.
- [ ] **Focused test:** the exact command ran now and its output is recorded.
- [ ] **Full suite:** the project's canonical full-suite command ran now and its
      output is recorded. Any failure is named in the report, including one you
      did not cause.
- [ ] **RED evidence:** for behavior changes, the failing test and its output
      are recorded before the fix.
- [ ] **Working tree:** `git status` matches what you are about to report;
      unrelated or generated changes are explained.
- [ ] **Files changed:** the list matches the diff, not the plan.
- [ ] **Commands and paths:** every command and path named in the report was run
      or read as stated.
- [ ] **Review findings:** every finding is fixed, rebutted with evidence, or
      reported open.

## Procedure

1. Run each verification command in the environment you are reporting on.
2. Read the output, including the exit code. Do not skim for the word "pass".
3. Compare the output with the claim you intend to make.
4. If they differ, report the failure or uncertainty. Do not soften it.
5. Record the command and the relevant output in the task report.

If the evidence is stale, partial, or from a different tree, the verification
failed. Re-run it or report that it could not be run and why.

## Common false claims

- "Tests pass" when only the focused test ran.
- "The suite is green" based on a worker's report you did not rerun.
- "Fixed" when the symptom was not reproduced or the root cause is unproven.
- "No other changes" when `git status` was not checked.
- "Documented" when the linked command was never executed.

Replace each with the command you ran and the output you saw, or with an honest
statement of what remains unverified.
