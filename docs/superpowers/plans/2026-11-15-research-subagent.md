# Research Subagent and Run-Research Skill — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a project-local OpenCode `research` subagent wired to Parallel Search and Brave Search MCP, and a `run-research` skill that fans out to research subagents and writes an evidence-backed report under a gitignored `research/` directory.

**Architecture:** MCP servers are configured in `opencode.jsonc` and exposed as native tools. `.opencode/agents/research.md` defines the reusable research worker with write access only under `research/`. `.opencode/skills/run-research/SKILL.md` orchestrates parallel research angles, an independent verification pass, and a final cited report. All artifacts are markdown in per-run folders under `research/`, which git ignores.

**Tech Stack:** OpenCode V2 config (JSONC), Markdown agents and skills, Brave Search MCP (local stdio), Parallel Search MCP (remote HTTP), git.

**Spec:** `docs/superpowers/specs/2026-11-15-research-subagent-design.md`

## Global Constraints

- Use OpenCode V2 shapes: `mcp.servers`, `disabled` (not `disable`), `.opencode/agents/`, `.opencode/skills/`.
- Parallel Search URL is exactly `https://search.parallel.ai/mcp`; no API key.
- Brave Search command is exactly `npx -y @brave/brave-search-mcp-server --transport stdio`; environment `BRAVE_API_KEY={env:BRAVE_API_KEY}`.
- The `research` agent runs in `mode: subagent` with model `opencode-go/deepseek-v4.1-flash`.
- The `research` agent may write only under `research/**`; shell is denied.
- The `research` agent uses Parallel Search and Brave Search MCP as its primary and only search path; OpenCode's built-in `websearch` is denied.
- The `research` agent may not launch subagents or ask the user; it must finish its brief and mark blocked facts `unverified`.
- Research artifacts are never tracked by git.
- The skill must be invocable as `@run-research <query>`.
- Do not commit changes unless the user explicitly asks.

## Review Focus

- **MCP tool-name mismatch:** the agent must be able to find and call both Parallel and Brave tools even though the server names are long and hyphenated. Verify by an actual tool call, not just `mcp list`.
- **Missing Brave key:** if `BRAVE_API_KEY` is absent or the npx server fails, the run must continue with Parallel and say so. It must not silently pretend both providers worked.
- **Path escape:** a subagent given an absolute or `../` path must not write outside `research/`. Permissions must enforce this, and the orchestrator must use repo-relative paths.
- **Blocked retailer pages:** Amazon/retail pages may block extraction. The report must mark availability or price as unverified rather than invent it.
- **Subagent reports without files:** a subagent may return a summary but fail to write its notes file. The orchestrator must check file existence and re-dispatch or do the angle itself.
- **Citation theater:** a report may include links that do not support the claim. The verifier must fetch the cited pages and match quotes/numbers/dates.

---

### Task 1: Configure MCP servers and the research subagent

**Files:**
- Modify: `opencode.jsonc`
- Create: `.opencode/agents/research.md`

**Interfaces:**
- Consumes: existing `$schema` and `plugins` config.
- Produces: MCP servers `parallel-search` and `brave-search-mcp-server`; subagent ID `research` with write access to `research/**`.

- [ ] **Step 1: Confirm the failing baseline**

Run:

```bash
opencode mcp list
opencode debug agents
```

Expected: `opencode mcp list` reports no configured servers, and `opencode debug agents` does not list `research`. Record the exact output.

- [ ] **Step 2: Add both MCP servers to `opencode.jsonc`**

Write this exact structure, preserving the existing plugin entry:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": [
    "superpowers@git+https://github.com/obra/superpowers.git"
  ],
  "mcp": {
    "servers": {
      "parallel-search": {
        "type": "remote",
        "url": "https://search.parallel.ai/mcp",
        "codemode": false,
        "disabled": false
      },
      "brave-search-mcp-server": {
        "type": "local",
        "command": [
          "npx",
          "-y",
          "@brave/brave-search-mcp-server",
          "--transport",
          "stdio"
        ],
        "environment": {
          "BRAVE_API_KEY": "{env:BRAVE_API_KEY}"
        },
        "codemode": false,
        "disabled": false,
        "timeout": {
          "startup": 60000
        }
      }
    }
  }
}
```

- [ ] **Step 3: Create `.opencode/agents/research.md`**

Use frontmatter with `description`, `mode: subagent`, and these permissions in order:

```yaml
permissions:
  - action: edit
    resource: "*"
    effect: deny
  - action: edit
    resource: "research/**"
    effect: allow
  - action: shell
    resource: "*"
    effect: deny
  - action: websearch
    resource: "*"
    effect: deny
  - action: "parallel-search_*"
    resource: "*"
    effect: allow
  - action: "brave-search-mcp-server_*"
    resource: "*"
    effect: allow
  - action: subagent
    resource: "*"
    effect: deny
  - action: question
    resource: "*"
    effect: deny
```

The body must state:

- The agent is a research worker, not the final report writer.
- Do not launch subagents; do the work yourself.
- Do not ask the user; if a fact is blocked, mark it `unverified` and return.
- Preferred tools: Parallel `web_search` (`objective`, `search_queries`) and `web_fetch` (`urls`, `objective`); Brave `brave_web_search`, `brave_llm_context`, `brave_news_search`.
- Every factual claim needs a source URL, publish/update date when available, access date, and confidence.
- Prefer primary sources; cross-check key claims with two independent sources.
- Separate observation from inference; label inference explicitly.
- For products, record price, currency, region, seller, availability, rating count, and review date.
- Never invent URLs, quotes, prices, dates, availability, or review counts. Mark blocked or unverifiable claims as `unverified`.
- If one MCP is unavailable, continue with the other and say so.
- Write to the exact markdown path in the brief, using repo-relative paths under `research/`, with the required notes structure: title, brief, date, MCPs used, queries, numbered findings with evidence/source/date/confidence, source table, gaps and conflicts, and a summary for the orchestrator.
- Return a short summary plus the path written. Do not write outside `research/`.

- [ ] **Step 4: Verify MCP connections**

Run:

```bash
opencode mcp list
```

Expected: `parallel-search` connected, `brave-search-mcp-server` connected. If Brave times out on the first npx download, rerun once; if it still fails, inspect `BRAVE_API_KEY`, network access, and the server timeout.

- [ ] **Step 5: Verify the research agent is discovered**

Run:

```bash
opencode debug agents
```

Expected: a `research` entry with `mode: subagent` and the configured description.

- [ ] **Step 6: Smoke-test one real search and write**

Run a primary agent with a narrow brief so the research agent must call a search MCP and write a file:

```bash
opencode run --agent build --auto --format json \
  "Use the research subagent to search for the Model Context Protocol specification. Tell it to write 3 bullet points with one source URL to research/smoke/notes-smoke.md and nothing else."
```

Expected: the command succeeds, `research/smoke/notes-smoke.md` exists and is non-empty, and it contains a `https://` URL.

Verify:

```bash
test -s research/smoke/notes-smoke.md
grep -q 'https://' research/smoke/notes-smoke.md
```

Remove the smoke artifact:

```bash
rm -rf research/smoke
```

- [ ] **Step 7: Verify the write guard outside `research/`**

Run the research agent with a request to write outside its allowed directory:

```bash
opencode run --agent research --auto \
  "Write the word 'test' to docs/permission-test.md. Do not use shell."
test ! -e docs/permission-test.md
```

Expected: the file does not exist because the edit permission denies paths outside `research/**`. If the file exists, remove it and fix the permission order in `.opencode/agents/research.md` before continuing.

- [ ] **Step 8: Review the diff**

Run:

```bash
git diff -- opencode.jsonc
git status --short
```

Expected: only `opencode.jsonc` and `.opencode/agents/research.md` are new or modified. Do not commit.

---

### Task 2: Write the run-research skill and report template

**Files:**
- Create: `.opencode/skills/run-research/SKILL.md`
- Create: `.opencode/skills/run-research/references/report-template.md`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: subagent ID `research`, MCP servers from Task 1.
- Produces: skill ID `run-research`; report skeleton at `.opencode/skills/run-research/references/report-template.md`; gitignore rule `research/`.

- [ ] **Step 1: Add `research/` to `.gitignore`**

Append:

```gitignore

# Research artifacts (local, evidence-backed reports)
research/
```

Verify:

```bash
git check-ignore -v research/baseline/report.md
```

Expected: the output names `.gitignore` and the `research/` rule.

- [ ] **Step 2: Run the RED baseline without the skill**

Dispatch a `general` subagent with this prompt (no skill loaded):

```text
Research the best budget USB-C cable under $15. Write a markdown report to
research/baseline/report.md with a recommendation and source links. Use web
search and fetch pages where useful. Do not use any skill.
```

Record the baseline behavior in `research/baseline/observation.md` (gitignored). Check specifically:

- Did it create per-claim evidence with source, date, and confidence?
- Did it use both Parallel and Brave MCP tools?
- Did it verify its recommendation with an independent pass?
- Did it record access dates and distinguish fact from inference?
- Did it check that the file it claims to have written actually exists?

Expected baseline failures: at least two of the above are missing. This is the RED result the skill must fix.

- [ ] **Step 3: Write `.opencode/skills/run-research/SKILL.md`**

Frontmatter:

```yaml
---
name: run-research
description: Use when the user asks for evidence-backed research, a product recommendation, a comparison, or a decision that requires current web sources; fans out to research subagents and writes a cited report under research/.
---
```

The body must contain these sections and rules:

1. **Overview** — the primary agent plans, launches multiple `research` subagents, verifies, and writes the report; artifacts go to `research/<YYYY-MM-DD>-<slug>/`.
2. **When to use** — "find the best", "compare", "is X worth it", "what do people recommend", and any claim that needs current sources.
3. **Workflow** — frame the question (criteria, assumptions, decision rule); choose 3–5 independent angles (community sentiment, expert reviews, price/availability, reliability/complaints, alternatives); create `brief.md`; launch one `research` subagent per angle in parallel in the same turn; confirm every notes file exists and is non-empty; launch one independent verifier over the 3–6 decision-driving claims; write `verification.md`; synthesize `report.md` from the template; reply with bottom line, path, source count, and main uncertainty.
4. **Subagent brief contract** — every brief includes the overall question, decision rule, specific angle and sub-questions, source priorities, exact output path, evidence standard, and "use both Parallel and Brave; cross-check key claims with two independent sources."
5. **Evidence standard** — two independent sources for key claims; primary source preferred; record claim, source, URL, dates, quote/paraphrase, confidence; distinguish fact from inference; for prices/availability record currency, region, seller, date, and whether the listing was directly fetched; for community sentiment record community, thread date, visible sample size, and representativeness; report conflicts instead of averaging them.
6. **Failure handling** — MCP unavailable: continue with the other and note it; thin/blocked results: try different queries, site-specific searches, archives, direct fetch, then mark unverified; subagent returns no file: re-dispatch once with a narrower brief, then do the angle yourself; paywall: cite visible content and mark the rest unverified.
7. **Common mistakes** — one agent called a team; subagents writing the final report; search snippets treated as sources; prices without date/region; hiding conflicts.
8. **Finish** — do not commit research artifacts; `research/` is gitignored.

- [ ] **Step 4: Write `references/report-template.md`**

The template must contain:

```markdown
# <Question>

**Date:** YYYY-MM-DD
**Bottom line:** <one paragraph recommendation>
**Confidence:** high | medium | low

## Criteria and assumptions
| Criterion | Weight | Assumption |
| --- | --- | --- |

## Comparison
| Option | Price | Availability | Community sentiment | Expert evidence | Key trade-off |
| --- | --- | --- | --- | --- | --- |

## Recommendation
<The winning option, why it wins, and the runner-up by use case.>

## Evidence
### <Criterion or claim>
- **Claim:**
- **Evidence:**
- **Sources:** [title](url) — published/updated, accessed YYYY-MM-DD
- **Confidence:**
- **Counter-evidence:**

## What could change this answer
<Price changes, availability, new models, region differences, failed assumptions.>

## Gaps and conflicts
<Unverified claims, blocked sources, contradictory evidence, missing data.>

## Sources
| # | Source | URL | Date | Used for |
| --- | --- | --- | --- | --- |

## Research log
| Angle | Subagent notes | Verification |
| --- | --- | --- |
```

- [ ] **Step 5: Verify the skill loads**

Load the skill in the current session with the `skill` tool using ID `run-research`. If that is unavailable, run:

```bash
opencode run --agent build --auto --format json \
  "@run-research Reply with the skill base directory and the report template path. Do not start research."
```

Expected: the skill body loads and points to `.opencode/skills/run-research/references/report-template.md`.

- [ ] **Step 6: Verify gitignore and skill files**

Run:

```bash
git check-ignore -v research/anything/report.md
test -s .opencode/skills/run-research/SKILL.md
test -s .opencode/skills/run-research/references/report-template.md
```

Expected: the ignore rule matches and both files are non-empty.

- [ ] **Step 7: Review the diff**

Run:

```bash
git diff -- .gitignore
git status --short
```

Expected: `.gitignore` modified; skill files untracked; no `research/` artifacts listed. Do not commit.

---

### Task 3: Run the GREEN end-to-end test with the socket-wrench query

**Files:**
- Create at runtime (gitignored): `research/2026-11-15-*/*.md`

**Interfaces:**
- Consumes: `run-research` skill, `research` subagent, both MCP servers.
- Produces: a final `report.md` with a bottom-line recommendation, citations, verification, and a research log.

- [ ] **Step 1: Load the skill and run the user's example**

In the primary session, load `run-research` and send:

```text
@run-research find the best socket wrench that is recommended by community
users and is affordable, and is available currently on amazon
```

Expected: the agent frames assumptions (likely USD, US Amazon, a stated budget band), creates a run folder, and launches 3–5 research subagents in parallel.

- [ ] **Step 2: Verify the fan-out**

While the run is active or after it completes, confirm that the run folder contains:

```text
brief.md
notes-community.md
notes-expert.md
notes-price-availability.md
notes-reliability.md
verification.md
report.md
```

At minimum, there must be two or more per-angle notes files, a verification file, and a report. If any notes file is empty, the orchestrator must re-dispatch that angle or do the work itself.

- [ ] **Step 3: Check the evidence standard**

Run:

```bash
RUN_DIR="$(find research -maxdepth 1 -type d -name '2026-11-15-*' | sort | tail -1)"
test -s "$RUN_DIR/report.md"
grep -q 'https://' "$RUN_DIR/report.md"
grep -qi 'accessed' "$RUN_DIR/report.md"
grep -qi 'bottom line' "$RUN_DIR/report.md"
grep -qi 'confidence' "$RUN_DIR/report.md"
```

Then read the report and check:

- every recommendation traces to a cited source;
- the top pick has at least two independent sources;
- Amazon availability is either directly verified or explicitly marked unverified;
- prices include currency, region, seller, and date;
- conflicts and gaps are reported, not hidden.

- [ ] **Step 4: Check git hygiene**

Run:

```bash
git status --short
```

Expected: no `research/` paths appear. If they do, fix `.gitignore` before continuing.

- [ ] **Step 5: Close the RED/GREEN loop**

If the run failed the evidence standard, write down the exact failure, patch the skill or agent prompt, and rerun a narrower version of the same query. Repeat until the report satisfies the checks. Do not declare the skill working without a passing end-to-end run.

- [ ] **Step 6: Report the result**

Reply with the bottom line, the report path, the number of distinct sources, the main uncertainty, and any degraded mode (for example, Brave unavailable).

---

### Task 4: Document the capability and run final verification

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: the finished agent, skill, and gitignore rule.
- Produces: user-facing documentation and a final verification record.

- [ ] **Step 1: Add a Research subagent section to `README.md`**

Place it under "Project-local configuration" or immediately after the host-secrets section. Include:

- what the `research` subagent and `run-research` skill do;
- the `@run-research <query>` invocation with the socket-wrench example;
- the output layout under `research/<YYYY-MM-DD>-<slug>/`;
- the fact that `research/` is gitignored;
- the `BRAVE_API_KEY` requirement and the Parallel fallback;
- a note that reports are only as good as their sources and unverified claims are marked.

Add these paths to the "Files" table:

```text
.opencode/agents/research.md        Research subagent definition and permissions
.opencode/skills/run-research/      Research orchestration skill and report template
research/                           Local research artifacts (gitignored)
```

- [ ] **Step 2: Run final static checks**

Run:

```bash
opencode mcp list
opencode debug agents
git check-ignore -v research/example/report.md
```

Expected: both MCPs connected; `research` listed; the ignore rule matches.

- [ ] **Step 3: Verify no tracked research artifacts**

Run:

```bash
git status --short
git ls-files research
```

Expected: `git status --short` does not list anything under `research/`; `git ls-files research` prints nothing.

- [ ] **Step 4: Review the complete diff**

Run:

```bash
git diff --stat
git diff -- opencode.jsonc .gitignore README.md
```

Read the agent and skill files once more for contradictions, especially tool names, permission order, output paths, and the evidence standard. Do not commit.

- [ ] **Step 5: Hand back**

Summarize what changed, where the first test report lives, and any remaining uncertainty. If the user asks to commit, commit only the tracked config, agent, skill, template, docs, and README changes; never commit `research/`.
