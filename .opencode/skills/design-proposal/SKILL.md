---
name: design-proposal
description: Use when the design worker must turn a brief into two to four solution options with trade-offs, a recommendation, and a test strategy, without editing files or asking the user.
---

# Design proposal

## Overview

A design proposal makes a decision cheap to review. It offers real options, says
what each one costs, recommends one, and shows how the choice will be tested.
It is not a summary of the obvious path.

## Inputs

Read the brief and the repository evidence it names. If an input is missing,
state the assumption you will use in one line and continue. Do not ask the user;
report the gap to the orchestrator.

## Options

Produce two to four options. One option may be "do nothing" or "keep the current
design" when that is a real alternative. Three is usually enough. For each
option, give:

- **Shape** — the approach in two or three sentences.
- **Changes** — the files, interfaces, commands, or configuration it touches.
- **Trade-offs** — what it makes easy and what it makes hard.
- **Risks** — what can fail, what is hard to reverse, what it assumes.
- **Test strategy** — the seam the failing test will use and the behavior it
  pins.

Do not present a straw option to make the recommendation look good. Every
option must be one a reasonable maintainer could choose.

## Recommendation

Name one option. Explain why it wins against the decision rule: the criteria
that matter, in order. Say why each rejected option lost. If two options are
close, say what evidence would change the choice.

State what you are not deciding. A proposal that quietly settles an unrelated
question invites the wrong review.

## Test strategy

Every product change starts with a failing test. For the recommended option,
give:

- the test file and the test name;
- the behavior the test asserts and the exact failure it should produce first;
- the fixtures or fakes the test needs;
- the focused command and the full-suite command;
- any behavior that cannot be tested this way, with the reason.

Infrastructure and configuration changes need a static or runtime assertion in
the same style: it fails before the feature exists and passes after.

## Output

Return to the orchestrator:

1. the restated problem and assumptions;
2. the options, side by side in a table when the dimensions are the same;
3. the recommendation and the decision rule it satisfies;
4. the test strategy;
5. open questions for the orchestrator, each with the default you used.

Do not edit files. Do not launch subagents. Do not ask the user a question.

## Common mistakes

- **One option dressed as several.** Vary the mechanism, not the wording.
- **Trade-offs with no cost.** "More flexible" without saying what it costs is
  not a trade-off.
- **A recommendation with no decision rule.** The reviewer cannot check it.
- **A test strategy that tests the implementation.** Pin the behavior.
- **Settling scope silently.** Name it or leave it out.
