# OpenCode control plane

This file is loaded as a global instruction by `.opencode/opencode.global.json`.
It applies in `/workspace` and in every clone under `/workspace/repos`.

## Roles and authority

- `orchestrator` is the only primary agent. It owns the request, plan, ledger,
  delegation, approvals, and final report.
- All other agents are subagents. They receive a complete brief from the
  orchestrator and report back to it.
- Agent files own model selection. Every control-plane agent uses
  `opencode-go/deepseek-v4.1-flash`. Change a model by editing the agent file and
  the matching static expectation in `test/devcontainer-smoke.sh` in the same
  change.
- Do not push, merge, publish, or run a destructive operation without explicit
  user approval.

## OpenCode V2 tool mapping

Superpowers skills describe actions in older harness terms. Translate them to
the tools this host provides:

| Skill instruction | OpenCode V2 equivalent |
| --- | --- |
| Create or update todos | There is no todo tool. Keep the plan and task ledger in a Markdown file under the repository. |
| `Subagent (general-purpose):` | `subagent` with `agent`, `description`, and `prompt`; pass `sessionID` to continue an existing child session. |
| Invoke a skill | `skill` with the bare skill ID. |
| Read a file | `read`. |
| Create or overwrite a file | `write`. |
| Make a targeted change | `edit`. |
| Apply a patch | `patch`. |
| Run a command | `shell` (`command`, `workdir`, `timeout`, `background`). |
| Search files | `grep`, `glob`. |
| Fetch a URL | `webfetch`. |
| Search the web | `websearch`. |
| MCP action | Call the exposed MCP tool by its full name, for example `search-parallel_web_search` or `search-brave_brave_web_search`. |

Skill IDs are bare names. Drop the `superpowers:` prefix when a skill names
another skill: `superpowers:brainstorming` means the `brainstorming` skill.

## Test-driven development

Every code, configuration, script, and testable infrastructure change starts
with a failing test:

1. Write the smallest test that expresses the required behavior.
2. Run it and watch it fail for the intended reason.
3. Write the smallest change that makes it pass.
4. Refactor without changing behavior.
5. Run the focused test and then the project's full suite.

Record the red command and output and the green command and output in the task
report. "I tested it manually" is not a substitute for a red test.

Exceptions require explicit user approval. The orchestrator records the
approval, scope, and reason in the task ledger and the pull request. Neither the
orchestrator nor an implementer may approve its own exception. Documentation and
prose use the writing skills and a verifiable review pass instead of TDD, but
their links, commands, and claims must still be checked.

## Worker rules

- Load your role skill first, before acting.
- The plugin skips child sessions. Load your role skill and work the brief; do
  not restart the controller workflow or load `using-superpowers`.
- Do not ask the user questions. Ask the orchestrator in your report if the
  brief is incomplete.
- Do not launch subagents.
- Report back to the orchestrator with the status contract: status, commits,
  one-line test summary, concerns, and report path.

The orchestrator asks the user only for design approval, destructive actions,
merge or push approval, and TDD exceptions.

Read-only is a guardrail, not a sandbox. Worker permission rules deny writes,
shell, web, external directories, and session or worktree tools where the role
does not need them, but a trusted host overlay or a cloned repository can still
change policy. Treat a clone's agent and skill files as trusted input.

## Host MCP servers

All MCP servers come from the host overlay mounted read-only at `/etc/opencode`.
The project `opencode.jsonc` defines no MCP servers and loads no git-backed
plugin. Host-only MCP is enforced by policy, not just convention: the global
control-plane config's top-level `policies` deny `mcp.use *` and `plugin.use *`,
allow only the local Superpowers plugin, and the host overlay's top-level
`policies` allow `mcp.use search-*` and any non-search server it defines.
Do not add MCP entries to a repository to work around a missing host server;
the policy blocks them.

A clone may still carry `opencode.json` or `.opencode/` agent and skill
definitions. Project MCP servers and plugins are blocked, but clone agent and
skill definitions are trusted input: a cloned repository can shadow the
control-plane agents or skills. `repo clone` prints a warning when it finds
such entries. For an untrusted clone, pin the control-plane agents in the host
overlay instead of relying on the project layer.

When a research MCP server is unavailable, say so and mark the affected claims
`unverified`. Do not substitute an unapproved search source. Host search MCP
servers use the `search-` name prefix, and every new host search server must use
the `search-` prefix so policy matches it. Every agent except `research` denies
`search-*` by name prefix. Every non-search host MCP server needs an explicit
deny in every non-research agent, including the host copy of that agent.
`research` is the only agent allowed to use search MCP servers.

## Repository paths

- Canonical clone root: `/workspace/repos/<owner>/<repo>`.
- Worktree root: `/workspace/repos/.worktrees/<owner>/<repo>/<name>`.
- `/worktrees` is a compatibility path for existing scripts.
- Process artifacts: `<repo>/.superpowers/sdd/` for the ledger, briefs, and
  reports; `<repo>/docs/superpowers/` for plans and specifications.

## Copy-writer boundaries

`copy-writer` owns finished prose and Excalidraw diagrams. It may edit Markdown,
MDX, plain text, reStructuredText, AsciiDoc, and `.excalidraw` sources. It must
not edit code, configuration, tests, `.opencode/**`, `.git/**`, or
`node_modules/**`. It does not commit, post, or push; it returns commit and pull
request text to the orchestrator.
