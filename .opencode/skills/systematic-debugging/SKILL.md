---
name: systematic-debugging
description: Use when a test fails for an unclear reason or behavior is unexpected, to reproduce, isolate, find the root cause, make a minimal fix, and add a regression test.
---

# Systematic Debugging

## Overview

Debug by evidence, not by guessing. Reproduce the failure, narrow it, prove the
root cause, fix that cause with the smallest change, and lock the fix behind a
regression test.

**Do not guess-patch.** Changing code until the symptom disappears leaves the
real defect in place and hides it from the next change.

## Steps

### 1. Reproduce

- Run the failing command yourself and capture the full output.
- Record the exact command, the expected result, and the actual result.
- Confirm the failure is deterministic. If it is flaky, record the conditions
  and the observed rate instead of treating one run as proof.
- Check the working tree and environment: branch, uncommitted changes, tool
  versions, and any fixture or service the test needs.

### 2. Isolate

- Shrink the failing case to the smallest input or test that still fails.
- Bisect along the call path: which layer returns the wrong value first?
- Add temporary instrumentation only where it answers a specific question, and
  remove it before the final change.
- Compare a passing case with the failing case and list the differences.

### 3. Find the root cause

State the root cause as a falsifiable sentence: "X fails because Y receives Z
instead of W." Confirm it by changing one variable and observing the predicted
result. If the prediction fails, the hypothesis is wrong; return to isolate.

Do not proceed on a cause you cannot demonstrate.

### 4. Fix minimally

- Change only what the proven root cause requires.
- Follow `test-driven-development`: write the regression test first, watch it
  fail for the original reason, then apply the fix.
- Do not bundle refactoring or unrelated cleanup into the fix. Note it for a
  separate change.

### 5. Add a regression test

The regression test must fail against the old behavior and pass with the fix.
Keep it in the normal suite so the defect cannot return unnoticed.

### 6. Verify

- Run the focused regression test and record the passing output.
- Run the project's full suite and report every failure by name.
- Re-run the original reproduction to confirm the reported symptom is gone.

## Report

Record the reproduction command and output, the isolation evidence, the root
cause, the fix, the regression test, and the focused and full-suite results. If
the root cause is still unproven, say so and report the blocker instead of
shipping a guess.
