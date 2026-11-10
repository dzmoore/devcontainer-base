# Task List: Remove `kubectl-helm-minikube`

Status legend: `[ ]` pending, `[~]` in progress, `[x]` done, `[!]` blocked.

## Phase 0 — Baseline

- [x] Create branch `feature/remove-kubectl-helm-minikube`
- [x] Tag current HEAD `pre-kubectl-helm-pin`
- [x] Back up `.devcontainer/devcontainer-lock.json`
- [x] Record current image ID and tool versions
- [x] Confirm untracked SVG is excluded from all commits

## Phase 1 — Commit 1: preserve existing work

- [x] Stage only the pre-existing Dockerfile bumps/indentation
- [x] Fix the yq smoke assertion to derive from the Dockerfile
- [x] Update the README note about the yq assertion
- [x] Run `test/devcontainer-smoke.sh static`
- [x] Commit 1

## Phase 2 — Red: write failing tests first

- [x] Static: assert the feature is absent from config and lockfile
- [x] Static: assert `KUBECTL_VERSION`, `HELM_VERSION`, and four digest ARGs
- [x] Static: assert official URLs, `sha256sum --strict -c -`, and canonical Helm asset names
- [x] Static: assert `bash-completion` is in the apt block
- [x] Static: assert post-create Helm completion and version verification
- [x] Static: update the `minikube-config` comment
- [x] Pre-smoke: remove minikube, add exact kubectl/Helm versions, add minikube-absent and bash-completion checks
- [x] Runtime smoke: remove minikube, add exact versions, minikube-absent, Helm marker, and completion checks
- [x] Run `test/devcontainer-smoke.sh static` and confirm the expected red failure

## Phase 3 — Green: implement to pass the tests

- [x] Add kubectl/Helm ARGs and per-arch digest ARGs to the Dockerfile
- [x] Add `bash-completion` to the apt package list
- [x] Add the root-run kubectl/Helm install block before `USER $USERNAME`
- [x] Remove the feature from `.devcontainer/devcontainer.json`
- [x] Regenerate `.devcontainer/devcontainer-lock.json`; keep the diff to one removal
- [x] Add the Helm completion marker block to `post-create.sh`
- [x] Add kubectl/Helm version checks to `post-create.sh`
- [x] Run `test/devcontainer-smoke.sh static` and confirm green

## Phase 4 — Documentation

- [x] README: remove minikube from bullets and tables
- [x] README: add kubectl/Helm to pinned tools and notes
- [x] README: add trust model, skew, completion, and rollout notes
- [x] README: update the "Change tool versions" and lockfile troubleshooting sections
- [x] Commit 3 (separate): refresh stale yq/OpenCode/Spec Kit rows and badge

## Phase 5 — Validation

- [x] `test/devcontainer-smoke.sh guard`
- [x] `test/devcontainer-smoke.sh static`
- [x] `devcontainer build --workspace-folder .` (frozen build passed; lockfile updated deterministically)
- [x] `test/devcontainer-smoke.sh build`
- [x] `test/devcontainer-smoke.sh pre`
- [x] `test/devcontainer-smoke.sh up`
- [x] `test/devcontainer-smoke.sh idempotent`
- [x] `test/devcontainer-smoke.sh recreate`
- [x] `test/devcontainer-smoke.sh fresh`
- [x] `test/devcontainer-smoke.sh all` (optional; covered by individual gates plus `paste`)
- [x] `test/devcontainer-smoke.sh cleanup`
- [x] `devcontainer read-configuration --include-merged-configuration` checks
- [x] Manual kubectl/Helm completion checks
- [ ] Optional multi-arch gate (not run; residual risk)
- [x] Commit 2

## Phase 6 — Review and close-out

- [x] Security review: digests, URLs, architecture mapping, `--strict`, trust model
- [x] Final diff review: no unrelated changes, no SVG, no stale claims
- [x] Confirm feature, `minikube-config` volume, and Copilot customization are gone
- [x] Record residual risks and rollout notes

## Final result

- Commit 1: `3a9a6a5` — baseline bumps and self-maintaining yq assertion
- Commit 2: `74474a4` — feature removal, pinned kubectl/Helm installs, tests, and docs
- Commit 3: `67bd280` — README pinned-version sync
- Validation: `guard`, `static`, frozen `build`, `pre`, `up`, `idempotent`, `recreate`, `fresh`, `paste`, and `cleanup` all passed.
- Merged config: no `kubectl-helm-minikube` feature, no `minikube-config` mount, no feature-provided Copilot instruction.
- Runtime: kubectl `v1.37.2`, Helm `v4.3.1`, minikube absent, kubectl and Helm completion working.
- Optional multi-arch build gate not run; see residual risks in the plan.
