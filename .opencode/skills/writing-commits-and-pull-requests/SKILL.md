---
name: writing-commits-and-pull-requests
description: Use when writing a commit message, commit body, pull request title or description, pull request comment, review reply, or issue comment. Encodes Conventional Commits, the pull request description skeleton, the comment grammar, and the truth rules for claims about code and tests.
---

# Writing commits and pull requests

## Required background

Load `technical-writing` and `writing-clearly-and-concisely` first. This
skill adds the Git and GitHub formats. It does not replace the truth rules or
the sentence rules.

## Commit messages

Format: `<type>(<scope>): <subject>`

Allowed types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`,
`build`, `ci`, `chore`, `revert`.

- **Subject:** imperative mood, lower case after the colon, no trailing
  period, 72 characters or fewer, and specific enough to identify the change
  without the body.
- **Body:** blank line after the subject, then why the change exists and what
  it changes. Wrap at 72 characters. Use bullets when the change has
  independent parts.
- **Footers:** `Refs: #123`, `Closes: #123`, `BREAKING CHANGE: ...`, and
  `Signed-off-by: ...` only when the repository's history or policy uses
  them.
- **One logical change per commit.** If the diff contains unrelated changes,
  say so and propose a split. Do not hide the mix in the message.

Examples:

```text
fix(devcontainer): keep GitHub App errors on one line
```

```text
feat(agents): add copy-writer subagent

The research agent covers evidence gathering, but no agent owns finished
prose. Add a copy writer that loads the vendored technical-writer and
Elements of Style skills, writes documentation files, and returns commit
and pull request text for the caller to apply.
```

Do not narrate the diff. The diff shows what changed; the body explains why
it changed and what consequence it has.

## Pull request titles and descriptions

Title: the same shape as a commit subject, without the type prefix unless the
repository uses one in pull request titles. Read `gh pr list --limit 5` when
the repository's convention is unclear.

Description skeleton:

```markdown
## Summary

<What changed and why, in one to three sentences.>

## Changes

- <Change>
- <Change>

## Verification

- `<command>`: <actual result>
- <Manual check and what was observed>

## Risk and rollback

<What can break, how it would be detected, and how to undo it.>

## Issues

Closes #123
```

- Omit a section only when it truly does not apply. Do not leave placeholders.
- Every verification line names a command and its real result. If a check was
  not run, write `not run`.
- Include screenshots or recordings for visible UI changes.
- Keep the description proportional to the change. A one-line fix does not
  need five sections.

## Pull request comments and review replies

- Lead with the finding or the answer.
- Quote the line or the code you mean.
- Name the severity: `BLOCKER`, `WARNING`, `OBS`, or `question`.
- Propose the concrete change, or ask one precise question.
- Do not praise, apologize, or narrate your process.
- Do not approve or request changes on behalf of the user. Draft the comment
  and return it.
- When replying to a review, answer the point and say what changed. Do not
  restate the whole pull request.

## Truth rules

- A claim about behavior must trace to the diff, a test, a command output, or
  a source you were given.
- Never invent a test result, benchmark, link, reviewer, or approval.
- Mark an unknown as `[source wanted: ...]` or write `not run`.
- If the diff is too large or ambiguous to describe truthfully, say what you
  inspected and what you could not.
