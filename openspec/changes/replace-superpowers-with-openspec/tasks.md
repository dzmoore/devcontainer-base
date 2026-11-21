# Tasks

> Execution order: 1, 3, 2, 4, 5, 6, 7. Group 3 must land before group 2 so the
> native skills preserve the skill IDs the agent permissions require.

## 1. Pin and initialize OpenSpec

- [x] 1.1 Add `@fission-ai/openspec@2.1.1` and the Node 22.20+ requirement to `.devcontainer/post-create.sh`, then verify `openspec --version` prints `2.1.1` in a built container.
- [x] 1.2 Run `openspec init --tools opencode --scope project --profile core`, commit `openspec/` and `.agents/skills/`, and verify `openspec validate --strict` succeeds with no plugin file created.

## 2. Remove the Superpowers runtime

- [x] 2.1 Remove the plugin entry from `.opencode/opencode.global.json` and verify a new session starts with the orchestrator and no Superpowers bootstrap.
- [x] 2.2 Delete `.opencode/superpowers/`, `.opencode/superpowers.lock`, `.opencode/superpowers-local.patch`, and `scripts/update-superpowers.sh`, then verify the paths are gone and `git grep -i superpowers` returns only historical documentation.
- [x] 2.3 Update `test/devcontainer-smoke.sh` to assert the vendored tree is absent and the OpenSpec tree is present, and verify the static suite fails before the code change and passes after.

## 3. Add native skills

- [x] 3.1 Write `.opencode/skills/test-driven-development/SKILL.md` with red, green, refactor, the evidence format, and the exception policy, then verify the implementer prompt references the same skill ID.
- [x] 3.2 Write `.opencode/skills/systematic-debugging/SKILL.md` with reproduce, isolate, root cause, minimal fix, and regression test, then verify a sample bug report follows it.
- [x] 3.3 Write `.opencode/skills/verification-before-completion/SKILL.md` with the evidence checklist, then verify the implementer and validator prompts reference it.
- [x] 3.4 Write `.opencode/skills/receiving-code-review/SKILL.md` with the finding-triage and verification loop, then verify the implementer prompt references it.
- [x] 3.5 Write `.opencode/skills/using-git-worktrees/SKILL.md` with create, move, remove, and path rules, then verify the commands against a scratch repository.
- [x] 3.6 Write `.opencode/skills/finishing-a-development-branch/SKILL.md` with test, review, commit, merge, and cleanup, then verify the checklist against a scratch branch.
- [x] 3.7 Extend `.opencode/skills/orchestration/SKILL.md` with the OpenSpec artifact flow and the OpenSpec/validator boundary, remove references to `brainstorming`, `writing-plans`, and `subagent-driven-development`, then verify it names `openspec propose` and does not name `/openspec-apply-change` as the implementation controller.

## 4. Rewire agents and instructions

- [x] 4.1 Update `.opencode/AGENTS.md` to remove Superpowers skill references, add OpenSpec commands, and keep the TDD policy and worker rules, then verify every referenced skill exists.
- [x] 4.2 Update `.opencode/agents/orchestrator.md` and `task-enumerator.md` for OpenSpec artifacts and task briefs, then verify the static checks.
- [x] 4.3 Update `implementer.md` and `validator.md` to reference the native TDD and verification skills, then verify the prompts require RED/GREEN evidence and an independent rerun.
- [x] 4.4 Update `design.md` and `rubber-duck.md` to use OpenSpec design artifacts for critique, then verify a dry-run design review.

## 5. Documentation and attribution

- [ ] 5.1 Update the README path table and workflow section to remove Superpowers, add OpenSpec, document `openspec init` per repository, and state the 2.1.1 pin.
- [ ] 5.2 Update `NOTICE` to remove Superpowers attribution and add OpenSpec MIT attribution for the generated skills.
- [ ] 5.3 Add a migration note for consumers covering the breaking change, the initialization step, and rollback.

## 6. Integration verification

- [ ] 6.1 Run `test/devcontainer-smoke.sh` and fix any failures, then verify exit 0.
- [ ] 6.2 In a disposable repository, run `openspec init`, create a change, validate it, and archive it, then verify the living spec updates and no plugin is required.
- [ ] 6.3 Run the orchestrator on a small task using the new flow, then verify the proposal, tasks, RED/GREEN evidence, validator PASS, and security-reviewer PASS.

## 7. Final gates

- [ ] 7.1 Dispatch the validator on the full tree and verify PASS with command output.
- [ ] 7.2 Dispatch the security-reviewer and verify PASS or fixed findings.

## Workflow follow-up

- Archive the change after the project's review requirements are satisfied.
- Verify the archived result.
