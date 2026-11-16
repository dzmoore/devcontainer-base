# Research Subagent and Run-Research Skill — Design

**Date:** 2026-11-15
**Status:** Approved in conversation

## Intent

Give this repository an OpenCode research capability that turns a question into an evidence-backed report. A project-local `research` subagent uses the Parallel Search and Brave Search MCP servers. A `run-research` skill fans work out to one or more research subagents, verifies the claims that drive the answer, and writes a cited report inside the repository.

The motivating request: `@run-research` should be able to answer a question such as "find the best socket wrench that is recommended by community users, is affordable, and is currently available on Amazon" with a recommendation that is traceable to current sources.

## Goals

- Configure both search MCP servers in the project OpenCode config.
- Add a reusable `research` subagent that can search, fetch, and write cited notes.
- Add a `run-research` skill that plans the work, launches parallel research subagents, runs an independent verification pass, and synthesizes a report.
- Write all research artifacts as markdown under a per-run folder in `research/`.
- Keep `research/` out of git.
- Make the capability discoverable and usable with `@run-research <query>`.

## Non-goals

- Building a general-purpose web scraper or crawler.
- Replacing OpenCode's built-in `websearch` provider.
- Committing research reports or evidence notes to the repository.
- Automatically publishing reports outside the repository.
- Adding a new test framework or CI workflow.

## Anti-goals

- A report that looks authoritative but has unsupported claims.
- A single agent pretending to be a research team.
- Research artifacts leaking into tracked files.
- Silent failure when one search MCP is unavailable.
- Fabricated URLs, quotes, prices, availability, or review counts.

## Constraints

- Use OpenCode V2 configuration shapes: `mcp.servers`, `disabled` (not `disable`), `.opencode/agents/`, and `.opencode/skills/`.
- Parallel Search uses `https://search.parallel.ai/mcp` and needs no API key.
- Brave Search runs locally with `npx -y @brave/brave-search-mcp-server --transport stdio` and `BRAVE_API_KEY={env:BRAVE_API_KEY}`.
- The research agent may write only under `research/**` and must not use shell commands.
- The skill must work when invoked as `@run-research <query>`.
- No research artifacts may appear in `git status`.
- Do not commit changes unless the user asks.

## Approaches Considered

1. **One general research agent does everything.** Simple, but slow, shallow, and hard to verify. Rejected.
2. **Fan-out to several research subagents, then verify.** Chosen. Independent angles reduce blind spots, parallel work is faster, and a separate verification pass makes the evidence standard enforceable.
3. **Expose MCP tools through Code Mode.** Works, but tool names and invocation are less predictable for a specialized research agent. Chosen alternative: `codemode: false`, exposing native tools with stable names.
4. **One final report file only.** Easy to read, but loses the evidence trail. Chosen alternative: a per-run folder containing the brief, per-angle notes, verification, and the final report.

## Design

### MCP configuration

`opencode.jsonc` gains two servers under `mcp.servers`:

- `parallel-search`: remote, `https://search.parallel.ai/mcp`, native tools.
- `brave-search-mcp-server`: local stdio server via `npx`, `BRAVE_API_KEY` from the environment, native tools.

### Research subagent

`.opencode/agents/research.md` defines a `mode: subagent` agent named `research`, pinned to `opencode-go/deepseek-v4.1-flash`. It:

- uses Parallel `web_search` / `web_fetch` and Brave `brave_web_search` / `brave_llm_context` / `brave_news_search`;
- prefers primary sources and records claim, source, date, quote, and confidence;
- cross-checks key claims against at least two independent sources;
- writes only to the exact markdown path in its brief;
- returns a short summary and the path to its notes;
- degrades gracefully when one MCP is unavailable.

Permissions deny shell, deny edits outside `research/**`, deny subagent delegation, and deny user questions. The agent must finish its brief and mark blocked facts `unverified` rather than delegating or blocking on input.

### Run-research skill

`.opencode/skills/run-research/SKILL.md` defines the orchestration workflow:

1. Frame the question: criteria, assumptions, decision rule, and 3–5 independent angles.
2. Create `research/<YYYY-MM-DD>-<slug>/brief.md`.
3. Launch one `research` subagent per angle in parallel; each writes `notes-<angle>.md`.
4. Confirm every notes file exists and is non-empty.
5. Launch one independent `research` verifier over the 3–6 claims that drive the recommendation; it writes `verification.md`.
6. Synthesize `report.md` using `references/report-template.md`.
7. Reply with the bottom line, report path, source count, and main uncertainty.

### Output layout

```text
research/
└── 2026-11-15-socket-wrench/
    ├── brief.md
    ├── notes-community.md
    ├── notes-expert.md
    ├── notes-price-availability.md
    ├── verification.md
    └── report.md
```

`research/` is added to `.gitignore`.

## What Is Left to the Builder

- Exact wording of the agent system prompt and skill instructions.
- Exact report template headings.
- Whether to add a short README section (yes) and where.
- Test query for the baseline and the end-to-end run.
