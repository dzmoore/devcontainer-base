# Proposal

## Why

The control plane vendors Superpowers as a 405-line plugin, a 323-line local patch, 11 script files, a lock file, and a 153-line updater. The tree is patched to fit OpenCode and the named agents, so the project pays the cost of a third-party runtime while already owning the orchestration, TDD, validation, and security gates it needs. Replace the vendored runtime with OpenSpec as the spec and planning layer, keeping the existing named agents and gates.

## What Changes

- Remove the vendored Superpowers tree, plugin, local patch, lock file, update script, and the smoke assertions that pin them.
- Adopt OpenSpec 2.1.1 as the spec layer. `openspec init` creates `openspec/` and six Markdown skills in `.agents/skills/`; there is no plugin and no script.
- Keep the nine named agents and their permission model: orchestrator, design, task-enumerator, implementer, validator, security-reviewer, research, rubber-duck, copy-writer.
- Keep the orchestrator as the only controller. Use OpenSpec to create and archive proposal, specs, design, and tasks, but not to run implementation.
- Extend the existing orchestration skill with the OpenSpec flow and add six native process skills: test-driven development, systematic debugging, verification before completion, receiving code review, git worktrees, and finishing a branch.
- **BREAKING** for consumers of this devcontainer: Superpowers is no longer loaded, and OpenSpec 2.1.1 becomes a required CLI. The README and smoke suite will document and verify the migration.

## Capabilities

### New Capabilities

- `control-plane-workflow`: the orchestrator-led spec to plan to tasks to TDD implementation loop, including named subagent dispatch and independent validation gates.
- `spec-artifacts`: the OpenSpec artifact lifecycle, including initialization, change folders, living specs, archive, and the boundary between OpenSpec verification and the project's validation gate.

### Modified Capabilities

None. This repository has no existing OpenSpec capabilities.

## Impact

- `.opencode/opencode.global.json`, `.opencode/AGENTS.md`, `.opencode/agents/*`, `.opencode/skills/*`, `.opencode/superpowers*`, `scripts/update-superpowers.sh`, `test/devcontainer-smoke.sh`, `README.md`, and `NOTICE`.
- `.devcontainer/post-create.sh` gains a pinned `@fission-ai/openspec@2.1.1` installation and the Node 22.20+ requirement.
- Every target repository that uses the workflow must run `openspec init` once. The control plane will detect a missing `openspec/` root and stop rather than create it implicitly.
