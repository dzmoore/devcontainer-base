---
name: run-research
description: Use when the user asks for evidence-backed research, a product recommendation, a comparison, or a decision that requires current web sources.
---

# Run research

## Overview

You are the orchestrator. You frame the question, launch several `research`
subagents in parallel, verify the claims that drive the answer, and write the
final report yourself. Research workers gather one angle each and write cited
notes; they never write the final report.

All artifacts go in one run folder under `research/`:

```text
research/<YYYY-MM-DD>-<slug>/
├── brief.md
├── notes-community.md
├── notes-expert.md
├── notes-price-availability.md
├── notes-reliability.md
├── notes-alternatives.md   # optional fifth angle
├── verification.md
└── report.md
```

`<YYYY-MM-DD>` is the run date. `<slug>` is lowercase ASCII words separated by
hyphens, derived from the question (for example,
`research/2026-11-15-socket-wrench/`). Use repo-relative paths only. The skill
base directory is `.opencode/skills/run-research`; the report template is
`.opencode/skills/run-research/references/report-template.md`.

## When to use

Use this skill for questions such as "find the best...", "compare...", "is X
worth it?", and "what do people recommend?". Use it for any answer that depends
on current prices, availability, reviews, community sentiment, or other facts
that change over time.

Do not use it for stable conceptual questions you can answer from existing
knowledge, or when the user explicitly wants a quick unsourced opinion.

## Workflow

### 1. Frame the question

Before searching, write down:

- a one-sentence restatement of the question;
- the criteria that matter and their relative weights;
- the assumptions you must make (budget, currency, region, use case, timeline);
- the decision rule that will pick a winner (for example, "lowest total cost
  that still meets the must-have criteria").

If a missing fact would change the decision, state the assumption you are using
and list it under "What could change this answer".

### 2. Choose 3–5 independent angles

Pick angles that can be researched independently and that reduce blind spots.
Use these standard names so the run folder stays predictable:

| Angle | Notes file |
| --- | --- |
| Community sentiment | `notes-community.md` |
| Expert or professional reviews | `notes-expert.md` |
| Price and availability | `notes-price-availability.md` |
| Reliability, defects, and complaints | `notes-reliability.md` |
| Alternatives and trade-offs | `notes-alternatives.md` |

Use three to five angles; never more than five. Fold extra questions into the
closest standard angle. For a product recommendation, the default set is
community sentiment, expert reviews, price/availability, and reliability; add
alternatives when the user is choosing between specific products. Add the fifth
only when it adds real information. Do not split one angle into two files just
to reach the minimum.

### 3. Create the run folder and `brief.md`

Create `research/<YYYY-MM-DD>-<slug>/` and write `brief.md`. It is the shared
contract for the run and must contain the overall question, criteria,
assumptions, decision rule, chosen angles, and the full evidence standard. Add
one subsection per angle with that angle's sub-questions and exact notes path.

### 4. Launch one `research` subagent per angle, in parallel, in the same turn

Use the `subagent` tool once per angle, all in one assistant turn, each with the
`research` agent. "Parallel" means the calls are issued together, not one after
another waiting for each result. One subagent is not a team; never collapse the
angles into a single worker.

Every subagent brief must satisfy the contract below and must name its exact
output path, for example `research/2026-11-15-socket-wrench/notes-expert.md`.
Never give a subagent an absolute path or a path outside `research/`.

### 5. Confirm every notes file exists and is non-empty

After the fan-out returns, check each path you dispatched with `test -s`. List
the exact notes files, not a glob, so a missing file is reported:

```bash
# Replace with this run's actual folder before running.
RUN_DIR="research/2026-11-15-socket-wrench"
for f in "$RUN_DIR"/notes-community.md "$RUN_DIR"/notes-expert.md \
         "$RUN_DIR"/notes-price-availability.md "$RUN_DIR"/notes-reliability.md; do
  test -s "$f" || echo "MISSING_OR_EMPTY: $f"
done
```

Adapt the list to the angles you actually dispatched.

A subagent saying "I wrote the file" is not evidence. Open or stat each expected
file. If a notes file is missing or empty, follow the failure handling below. Do
not start the report until every dispatched angle has usable notes.

### 6. Run one independent verifier

Select the 3–6 claims that drive the recommendation: the claims that, if wrong,
would change the winner or the confidence level. Dispatch one new `research`
subagent that did not research an angle. Its brief must list the exact claims,
point to the notes files, and require it to:

- fetch the cited pages rather than relying on notes or snippets;
- match the quoted text, numbers, dates, and product/version names;
- label each claim `verified`, `contradicted`, or `unverified`;
- report what it actually fetched and what was blocked.

It writes `research/<YYYY-MM-DD>-<slug>/verification.md`. Confirm that file
exists and is non-empty before writing the report.

### 7. Write `report.md`

Synthesize `research/<YYYY-MM-DD>-<slug>/report.md` from
`.opencode/skills/run-research/references/report-template.md`. Fill every
section; do not leave placeholders. Keep the report's claims traceable to the
notes and to sources the verifier checked. If the verifier contradicts a claim,
change the recommendation or downgrade confidence and report the conflict.

Count the distinct sources in the Sources table. Include the angle notes and
`verification.md` in the Research log.

### 8. Reply

Reply with:

- the bottom line in one or two sentences;
- the repo-relative report path;
- the number of distinct sources;
- the main uncertainty or conflict.

Do not paste the whole report into the chat.

## Subagent brief contract

Every subagent brief must include all of the following:

- **Overall question** — the user's question and the run's scope.
- **Decision rule** — the exact rule the final report will apply.
- **Specific angle and sub-questions** — one angle only, with the concrete
  questions it must answer.
- **Source priorities** — primary sources first; then independent expert or
  testing sources; then community discussion. Name the sites worth trying.
- **Search tools** — Host search MCP servers use the `search-` name prefix and
  are the primary and only search path. Do not use OpenCode's built-in
  `websearch`; it is disabled for the research agent. Fetch specific pages only
  after a search result gives you a URL.
- **Exact output path** — a repo-relative path under `research/`, such as
  `research/2026-11-15-socket-wrench/notes-community.md`.
- **Evidence standard** — the claim/source/URL/date/quote/confidence format,
  fact-versus-inference labeling, and conflict reporting from this skill.
- **Required sentence** — "Use every configured `search-*` MCP server as the
  primary search path; cross-check key claims with two independent sources."
- **Boundaries** — write only the exact output path, do not use shell, do not
  launch subagents, do not ask the user, and mark blocked facts `unverified`.
- **Return format** — a short summary plus the exact path written.

The verifier's brief uses the same contract, with the 3–6 claims and
`verification.md` as its output instead of an angle and a notes file.

## Evidence standard

- **Two independent sources for key claims.** Independence means different
  publishers, not two pages that copy the same press release.
- **Primary sources first.** Prefer specifications, official documentation,
  manufacturer or retailer pages, filings, and original test data. Treat search
  snippets, aggregators, and AI summaries as leads, not evidence.
- **Record every finding** with: claim; source title; URL; publish or update
  date; access date; direct quote or paraphrase; confidence (`high`, `medium`,
  or `low`).
- **Distinguish fact from inference.** Quote or paraphrase what the source
  actually says, then label any inference explicitly as `inference`.
- **Prices and availability:** record currency, region, seller, date, and
  whether the listing was directly fetched. If the listing was not fetched,
  write `unverified` for the price or availability field.
- **Community sentiment:** record the community, thread or post date, visible
  sample size, and how representative the sample is. A few enthusiastic posts
  are not a consensus.
- **Report conflicts instead of averaging them.** Show both values or claims,
  name the sources, and explain which one the recommendation relies on and why.
- **Never invent** URLs, quotes, prices, dates, availability, ratings, or
  review counts. Mark blocked or unverifiable claims `unverified`.

## Failure handling

- **MCP unavailable:** continue with the other search provider and state plainly
  in the notes and report which provider was unavailable. Never claim both
  worked when only one did. If both MCPs are unavailable, use direct `webfetch`
  on known URLs where possible and mark the rest `unverified`; do not fall back
  to OpenCode's built-in `websearch`.
- **Thin or blocked results:** try different queries, site-specific searches,
  archives, and direct fetches of the underlying page. If the fact still cannot
  be confirmed, mark it `unverified` and say what was blocked.
- **Subagent returns no file or an empty file:** re-dispatch that angle once
  with a narrower brief. If it still fails, do the angle yourself. Never
  synthesize a report from missing notes. If the primary agent covers an angle
  after a worker failure, write the same notes path with a `source: primary
  agent` line and record the fallback in the Research log.
- **Verifier returns no file or an empty file:** re-dispatch the verifier once
  with a narrower claim list. If it still fails, mark the selected claims
  `unverified`, downgrade confidence, and record the missing independent
  verification in "Gaps and conflicts." Do not self-verify and call it
  independent.
- **Paywall:** cite the visible content and mark the rest `unverified`; do not
  infer the hidden text.
- **Verifier contradicts or cannot confirm a claim:** change the recommendation
  if needed, downgrade confidence, and put the contradiction in "Gaps and
  conflicts".

## Common mistakes

- **One agent called a team.** A single worker covering every angle is not a
  fan-out and hides blind spots.
- **Subagents writing the final report.** Workers write notes only; the verifier
  writes verification only; the primary agent writes `report.md`.
- **Using built-in `websearch` instead of the MCPs.** The `search-*` servers are
  the primary search path; built-in search is disabled for the research agent.
- **Search snippets treated as sources.** Open the page and quote what it says.
- **Prices without date, region, or seller.** A price is not a fact without
  those fields.
- **Hiding conflicts.** Contradictory evidence belongs in the report, not in a
  silent average.
- **Starting the report before the notes exist.** Check every file first.
- **Absolute paths or `../` paths in subagent briefs.** Use repo-relative paths
  under `research/` only.

## Finish

Write artifacts only under `research/`, which is gitignored. Do not commit
research artifacts. Leave the run folder in the working tree and report the
repo-relative path to `report.md`.
