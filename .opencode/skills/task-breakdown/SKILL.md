---
name: task-breakdown
description: Use when an approved design must become ordered, independently testable TDD tasks with files, interfaces, a failing test, red and green steps, a verification command, dependencies, and a parallelization decision.
---

# Task breakdown

## Overview

A task is the unit one implementer can finish in one session, test first, and
hand to a validator without guessing. Break the work into vertical slices:
each task delivers observable behavior, not a layer of scaffolding.

## Vertical slices

Prefer a thin end-to-end slice over a horizontal layer. "Add the parser, then
the writer, then the caller" leaves three tasks that cannot be tested alone.
"Given one input, the command returns the parsed value" is a slice with a real
red step.

Keep a slice small enough that its diff can be reviewed in one pass. If a task
needs more than one failing test to express its behavior, it is probably two
tasks.

## Required fields per task

```text
Task <N>: <imperative title>

Files:
  - <path to create or modify>

Interfaces:
  - <public function, command, config key, or contract this task establishes or
    consumes>

Failing test:
  - <test file path and test name>
  - Asserts: <the behavior, in one sentence>

RED step:
  - Command: <exact command>
  - Expected failure: <the assertion that must fail, for the intended reason>

GREEN step:
  - Change: <the smallest change that makes it pass>
  - Command: <exact command that must pass>

Refactor:
  - <what to clean up without changing behavior>

Verification:
  - Focused: <exact command>
  - Full suite: <exact command>

Dependencies:
  - <task ids that must land first, or "none">

Parallelization:
  - <safe to run with task X, or "serial: shares <files> with task Y">
```

The RED step is mandatory. A task that cannot name a failing test needs a user
approval for a TDD exception, recorded by the orchestrator. Do not invent a test
that passes before the change.

## Ordering rules

1. Dependencies first. A task that consumes an interface lands after the task
   that introduces it.
2. Test-first within every task. Do not batch tests in a separate task.
3. One concern per task. A rename plus a behavior change is two tasks.
4. Gates last. Full-suite validation and security review are not implementer
   tasks; they are the `validator` and `security-reviewer` gates.
5. Documentation is its own pass after behavior is verified, except where a
   policy change requires the document and the code in the same change.

## Parallelization

Two tasks may run in parallel only when they touch disjoint files and neither
depends on the other's interface. When in doubt, mark them serial. A plan that
schedules parallel implementers on shared files creates merge conflicts and
contradictory tests.

Name the shared file when a task is serial, so the orchestrator can schedule it.

## Output

Return to the orchestrator:

1. the ordered task list, each with the fields above;
2. the dependency graph in one line per task;
3. the parallel groups, or "all serial";
4. tasks that need a TDD exception, with the reason;
5. the first task to dispatch.

Do not edit files. Do not launch subagents. Do not ask the user a question. If
the design is too vague to slice, say which decision is missing and stop.

## Common mistakes

- **Horizontal layers.** They cannot be tested alone.
- **Tests in a separate task.** The red step disappears.
- **A RED step that already passes.** It proves nothing.
- **Tasks that share files with no dependency.** They conflict.
- **Skipping the verification command.** The validator cannot reproduce the
  claim.
- **A task with no observable outcome.** It is scaffolding, not a slice.
