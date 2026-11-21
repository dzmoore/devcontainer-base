# Design

## Context

See proposal.md for motivation. The current control plane vendors Superpowers v7.0.2 under `.opencode/superpowers/` and loads it from `.opencode/opencode.global.json`. A local patch adds canonical TDD references, maps generic subagent prompts to the named agents, and removes per-dispatch model selection. The costs are a 405-line plugin, a 323-line patch, 11 script files, a lock file, a 153-line updater, and a large smoke-test surface that pins the vendored tree.

OpenSpec 2.1.1 was tested in a throwaway repository. `openspec init --tools opencode --scope project --profile core` created `openspec/config.yaml`, `openspec/changes/`, `openspec/specs/`, and six Markdown skills under `.agents/skills/`. OpenCode's documented discovery includes `.agents/skills/` as a project compatibility source, so no plugin is required. `openspec new change` and `openspec instructions` produce the proposal, specs, design, and tasks scaffold.

## Goals / Non-Goals

**Goals:**

- Remove the vendored Superpowers plugin, tree, patch, lock, updater, and scripts.
- Use OpenSpec for the durable spec and planning artifacts.
- Keep the orchestrator, named subagents, TDD evidence, validator, and security-reviewer gates.
- Keep the control plane small: agents plus a handful of local Markdown skills.

**Non-Goals:**

- Replacing the orchestrator or the implementer/validator loop with OpenSpec.
- Using OpenSpec's apply workflow as the implementation controller.
- Adopting OpenSpec Stores or a cross-repo planning service in this change.
- Rewriting the technical-writer, Elements of Style, diagramming, or commit/PR skills.

## Decisions

### Decision: OpenSpec owns artifacts, the orchestrator owns the process

OpenSpec creates and archives proposal, specs, design, and tasks. The orchestrator decides when a change is ready, dispatches one implementer per task, and requires validator and security-reviewer verdicts. The alternative, letting `/openspec-apply-change` run implementation, is rejected because it bypasses the named implementer, the TDD evidence format, and the independent gates.

### Decision: Remove the plugin and all vendored runtime code

The plugin, vendored tree, patch, lock, and updater are removed. OpenSpec is installed as a pinned CLI dependency, not committed as source. The generated `.agents/skills/openspec-*` Markdown is committed so the repository is reproducible and OpenCode can discover it without running `openspec update` first. The alternative, keeping the plugin and adding OpenSpec, was rejected because it doubles the planning surface and preserves the problem.

### Decision: Keep the existing agents and port only the missing skills

The nine agents remain. The native skill set is: the existing `orchestration` skill extended with OpenSpec steps, plus `test-driven-development`, `systematic-debugging`, `verification-before-completion`, `receiving-code-review`, `using-git-worktrees`, and `finishing-a-development-branch`. These IDs preserve the existing agent permission rules. The alternative, writing a complete new methodology, was rejected as unnecessary scope; the existing gates and prompts already encode most of it.

### Decision: Pin OpenSpec 2.1.1 and initialize per repository

The devcontainer image installs `@fission-ai/openspec@2.1.1` and requires Node 22.20 or newer. Each target repository runs `openspec init` once. The control plane detects a missing `openspec/` root and stops rather than creating it implicitly. The alternative, using `latest`, was rejected because OpenSpec shipped two breaking majors in eight days in November 2026.

## Risks / Trade-offs

- [OpenSpec is maintained by a small team and has breaking releases] -> Pin 2.1.1 in the image, treat upgrades as planned changes, and keep the generated skills under version control.
- [OpenSpec verification is non-blocking] -> Keep the validator as the completion gate and state the boundary in `spec-artifacts`.
- [The CLI adds a Node dependency to the devcontainer] -> Install it at image build time, document the Node 22.20 requirement, and keep it out of `post-create.sh`'s critical path where possible.
- [Generated skills can drift from the CLI version] -> Regenerate with `openspec update` during upgrades and let the smoke suite compare the expected skill set.
- [Removing Superpowers is a breaking change for consumers] -> Document the migration in README, keep the path table accurate, and add smoke assertions for both the absence of the plugin and the presence of the OpenSpec tree.
- [The workflow could accidentally use OpenSpec apply as the controller] -> State the boundary in `AGENTS.md` and the orchestration skill, and have the validator reject task reports that lack RED/GREEN evidence.

## Migration Plan

1. Pin and install OpenSpec 2.1.1 in the image.
2. Initialize OpenSpec in this repository and commit `openspec/` plus `.agents/skills/`.
3. Remove the Superpowers plugin from the global config and delete the vendored tree, patch, lock, and updater.
4. Add the native skills and rewire `AGENTS.md`, the orchestration skill, and the agent prompts.
5. Update README, NOTICE, and the smoke suite.
6. Run the full smoke suite and a dry-run change in a disposable repo.

Rollback: restore the previous commit. The OpenSpec tree is additive and does not alter existing project files until the agents are rewired.

## Open Questions

- Whether to use OpenSpec Stores for cross-repo planning. Deferred; Stores are beta and not needed for this change.
- Whether to commit generated skills from `openspec init` or regenerate them in `post-create.sh`. The design commits them for reproducibility; this can be revisited if the skill set churns.
