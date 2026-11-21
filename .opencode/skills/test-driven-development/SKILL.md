---
name: test-driven-development
description: Use when implementing a feature or bugfix, before writing implementation code, to drive the change through RED, GREEN, and REFACTOR with recorded evidence.
---

# Test-Driven Development

## Overview

Write the failing test first. Watch it fail for the intended reason. Make the
smallest change that passes. Refactor without changing behavior. Record the
commands and output you actually saw.

**Iron law:** no production change without a failing test that came first.

## When to use

Use this skill for every code, configuration, script, and testable
infrastructure change. Documentation and prose use the writing skills and a
verifiable review pass instead.

An exception needs explicit user approval. The orchestrator records the
approval, the scope, and the reason in the task ledger and the pull request.
Neither the orchestrator nor the implementer may approve its own exception.
Silence is not approval.

## The cycle

### 1. RED: write one failing test

Write the smallest test that expresses the required behavior. Give it a name
that states the behavior, and assert on real behavior rather than on a mock.

Run only that test first:

```bash
<focused test command with the test path or name>
```

Confirm all three:

- the test fails, rather than erroring on a typo or setup problem;
- the failure message names the missing behavior;
- it fails for the reason you intended, not because an import is wrong.

Record the exact command and the failure output in the task report. If the test
passes immediately, it does not test new behavior: fix the test before writing
implementation code.

### 2. GREEN: make the smallest change

Write the least code that makes the focused test pass. Do not add options,
abstractions, or unrelated cleanup. Do not weaken the test to fit the code.

Run the focused test again and confirm it passes with clean output.

### 3. REFACTOR: clean up while green

Remove duplication, improve names, and extract helpers only when the tests stay
green. Refactoring adds no behavior. After each step, rerun the focused test.

## Verify the whole change

Before reporting GREEN:

1. Run the focused test and record the passing output.
2. Run the project's full suite with the repository's canonical command, not
   only the test you touched.
3. Report any failure the full suite shows by name, including a failure you did
   not cause. A green focused test is not a green suite.
4. Report concerns and residual risk in the task report.

## Shortcuts that are not allowed

- Writing implementation code before the test, then adding a test after.
- Keeping untested code "for reference" and adapting it later.
- Marking a test `skip` or loosening an assertion to get green.
- Testing a mock or a stub instead of the behavior under test.
- Calling work done because it was checked by hand once.

If you catch yourself taking one of these shortcuts, delete the implementation
and start the cycle again from a failing test.
