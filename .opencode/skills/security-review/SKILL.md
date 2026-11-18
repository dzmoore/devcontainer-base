---
name: security-review
description: Use when a branch, script, permission set, or host MCP overlay needs a threat model and security review covering secrets, auth, injection, path traversal, dependency and supply chain, host overlay trust, docs-only MCP denies, and redaction.
---

# Security review

## Overview

Security review asks how the change can be abused, what it exposes, and what it
trusts that it should not. It covers the diff, the scripts it runs, the
permissions it grants, and the host configuration it depends on. The output is a
PASS or FAIL verdict with evidence. Never print a secret.

## Threat model first

Before reading the diff, write four lines:

1. **Assets** — what the change protects or can expose: credentials, source,
   user data, host configuration, container access.
2. **Trust boundaries** — host to container, repository to host overlay,
   orchestrator to worker, worker to shell, document to renderer.
3. **Inputs** — who controls the branch name, paths, URLs, environment
   variables, MCP responses, and filenames.
4. **Abuse cases** — the three most damaging realistic attacks against this
   change.

Then review against the model. A finding that does not fit the model is still a
finding; say why the model missed it.

## Checks

### Secrets

- Scan the diff and new files for tokens, keys, passwords, private keys,
  Authorization headers, and credential-bearing URLs.
- Confirm secret references use the host overlay path
  (`{file:/etc/opencode/secrets/...}`) and never a literal value.
- Confirm no secret is copied into logs, reports, test fixtures, or error text.
- If you find one, report the file and the variable name, replace the value with
  `<redacted>`, and treat it as a Blocker.

### Authentication and authorization

- Do not weaken the GitHub App helpers, their token handling, or their error
  reporting.
- Do not add a second credential store or a token cache.
- Check that a permission change grants only what the role needs. An edit or
  shell allow is a guardrail decision, so say what it permits.

### Injection

- Any shell command built from a variable is a candidate. Check quoting, word
  splitting, and command substitution.
- Check for `eval`, unquoted globs, and values interpolated into a command,
  a JSON document, or a Markdown renderer.
- A filename from a branch name or issue title is untrusted input.

### Path traversal

- Check that repository, worktree, ledger, and output paths stay under their
  root. Reject `..`, absolute paths from workers, and a path built from an
  untrusted name.
- Confirm tests and scripts cannot write outside the disposable copy.
- Check symlink handling: a link that escapes the root is a finding.

### Dependency and supply chain

- New dependencies need a pin and a reason.
- Check for `curl ... | sh`, unpinned downloads, floating tags, and installers
  that bypass the checksum pattern the repository uses.
- Vendored trees keep their pin, license, and provenance file.
- Review the update script: it fetches the pin, verifies the commit, and fails
  closed on drift.

### Host MCP and overlay trust

- The host overlay is mounted read-only and is the only MCP source. The project
  configuration must not enumerate servers or load a git-backed plugin.
- Host agent overrides replace the body, inherit unspecified fields, and append
  permission rules. They are trusted and can weaken TDD or security policy.
  Review them like code.
- Every non-research control-plane agent needs an explicit deny for every host
  search or write-capable MCP server. The two known servers,
  `parallel-search_*` and `brave-search-mcp-server_*`, must stay denied in
  every non-research agent (`orchestrator`, `copy-writer`, `design`,
  `rubber-duck`, `task-enumerator`, `implementer`, `validator`,
  `security-reviewer`). A new host server needs a manual deny in every
  non-research agent. `research` is the only agent allowed to use the research
  MCP servers.
- The overlay is integrity protection, not a confidentiality boundary. The
  container is privileged for Docker-in-Docker; say so when the change relies on
  isolation.

### Agent permissions

- Read-only workers keep `edit *` deny, `question *` deny, and `subagent *`
  deny.
- The orchestrator keeps its edit allow limited to the plan and ledger trees.
- The implementer may edit and run shell, but must keep the push and hard-reset
  denies and must not ask the user or launch subagents.
- A broad skill allow hides irrelevant skills; a broad MCP allow widens the
  attack surface.

### Files, modes, and generated output

- Executable helpers keep intended modes; credential files are not created
  world-readable.
- Generated and vendored files are not hand-edited.
- A renderer or generator does not overwrite a source it did not create.

## Redaction

- Never print a secret value, token fragment, key, or credential-bearing URL.
- Report the path and the variable name, not the value.
- If you must quote a line, replace the value with `<redacted>` and keep enough
  structure to locate it.
- Do not copy a secret into a report, a commit, or a finding's evidence block.

## Verdict

- **PASS** — no Blocker or Major finding, and the threat model's abuse cases are
  addressed or explicitly out of scope.
- **FAIL** — any unredacted secret, exploitable injection or traversal, unsafe
  download, widened permission without need, or missing docs-only deny.

Order findings by severity: Blocker, Major, Minor. Include the location, the
evidence, the abuse case, and the smallest fix.

## Report format

```text
Verdict: PASS|FAIL

Threat model:
  Assets: <...>
  Trust boundaries: <...>
  Inputs: <...>
  Abuse cases: <...>

Findings:
  [<severity>] <id> <title>
  Where: <file:line>
  Evidence: <redacted observation>
  Abuse case: <what an attacker does>
  Fix: <smallest change>

Checked: secrets, auth, injection, traversal, dependencies, host overlay,
  agent permissions, file modes
Residual risk: <what this review cannot prove>
```

## Boundaries

Do not edit files, ask the user, or launch subagents. Return the verdict to the
orchestrator. If a finding needs a code change, return FAIL and let the
orchestrator dispatch the implementer.

## Common mistakes

- **Reporting a secret value.** Redact it and stop repeating it.
- **Reviewing only the diff.** The scripts, permissions, and host overlay are
  part of the change.
- **Trusting the host overlay.** It is trusted by design, not proven safe.
- **Assuming the container is a sandbox.** It is privileged.
- **Ignoring a docs-only agent's MCP denies.** A new host server needs a new
  deny.
- **PASS with an unreviewed supply-chain change.** Pin it or fail it.
