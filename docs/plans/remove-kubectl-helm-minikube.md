# Plan: Replace `kubectl-helm-minikube` with Dockerfile-installed kubectl and Helm

- **Status:** Implemented — validated
- **Date:** 2026-11-09
- **Repository:** `dzmoore/devcontainer-base`
- **Scope:** Remove `ghcr.io/devcontainers/features/kubectl-helm-minikube:1`; install only kubectl and Helm in the Dockerfile; no minikube.

---

## 1. Summary

Replace the Dev Container feature `ghcr.io/devcontainers/features/kubectl-helm-minikube:1` with pinned, digest-verified installs of kubectl and Helm in `.devcontainer/Dockerfile`.

The feature currently installs kubectl, Helm, and minikube by default. This change:

- removes minikube entirely,
- pins kubectl and Helm to exact versions,
- verifies both downloads against per-architecture SHA256 digests,
- preserves functional bash completion,
- removes the feature's implicit volume, package installs, and VS Code customization,
- updates the lockfile, smoke tests, and documentation.

**Implementation complete; all validation gates passed.** See `remove-kubectl-helm-minikube.tasks.md` for the task-level record.

---

## 2. Research: the most official install path

The upstream documentation and live release assets were checked on 2026-11-08/09.

| Tool | Official methods | Recommendation |
| --- | --- | --- |
| **kubectl** | Direct binary from `dl.k8s.io` with SHA256 verification, or the apt repository at `pkgs.k8s.io` ([docs](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)) | Direct binary, pinned to **v1.37.2** |
| **Helm** | Binary tarball from `get.helm.sh`, or the official `get-helm-4` script ([docs](https://helm.sh/docs/intro/install/)) | Tarball, pinned to **v4.3.1** |

### Why direct artifacts instead of package managers

- The kubectl apt repository is a **per-minor moving channel** (`v1.37`), not an immutable patch archive. Exact patch pinning works today but is fragile and not reproducible over time ([docs](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/change-package-repository/)).
- Helm's apt repository is **community-maintained and explicitly not trusted by the Helm project**. At review time it lagged the current patch release.
- The official Helm install script is fetched from a moving `main` branch. The tarball avoids executing remote code and allows exact version pinning.
- Both kubectl and Helm are statically linked. `ca-certificates`, `curl`, `tar`, and `sha256sum` are already available in the image.

### Current versions

| Component | Version | Notes |
| --- | --- | --- |
| kubectl | `v1.37.2` | Current stable; supports Kubernetes 1.36–1.38 (±1 minor) |
| Helm 4 | `v4.3.1` | Current stable; Helm 4.3.x supports Kubernetes 1.34–1.37 |
| Helm 3 | `v3.22.1` | Final Helm 3 minor; security support ends 2027-02-10 |

---

## 3. What the rubber-duck review caught

The adversarial review identified several failure modes that the naive version of this change would miss:

1. **The kubectl checksum file is a bare hash.**
   It contains only the digest, not the `<digest>  <filename>` line GNU `sha256sum -c` expects. Without a synthetic line, verification is meaningless: on macOS `sha256sum -c kubectl.sha256` warns but exits `0`, while on Debian bookworm it exits `1` with `no properly formatted checksum lines found`. `--strict` additionally rejects checksum files that mix valid and malformed lines. The plan hardcodes digests and uses `sha256sum --strict -c -` with a synthetic line.

2. **Helm checksums require canonical filenames.**
   The `.sha256sum` file references `helm-v4.3.1-linux-amd64.tar.gz`, so the tarball must be saved under that exact name in a temp directory.

3. **`helm version --short` is not an exact version.**
   It returns `v4.3.1+gc0d08d0`. Tests must use `helm version --template '{{.Version}}'`.

4. **Removing the feature removes `bash-completion`.**
   Kubectl and Helm completions need `_init_completion` / `_get_comp_words_by_ref` from the `bash-completion` package at Tab time. Sourcing the completion script succeeds without it, but completion silently fails.

5. **Dropping Helm GPG verification would be a security regression.**
   The current feature GPG-verifies the Helm tarball. Replacing that with a same-origin checksum would weaken verification. This plan hardcodes the official per-arch SHA256 digests, anchoring trust in this repository.

6. **The feature contributes more than binaries.**
   It declares a `minikube-config` volume at `/home/vscode/.minikube` and injects a VS Code Copilot customization. Both disappear on removal.

7. **The lockfile must stay in exact parity with `devcontainer.json`.**
   The static test enforces set equality, and CLI regeneration can churn unrelated feature entries.

8. **A pre-existing test failure blocks validation.**
   The yq smoke assertion hardcodes `v4.54.1`, while the working tree pins `v4.54.3`. It must be made self-maintaining.

9. **The working tree has uncommitted changes.**
   The Dockerfile has version bumps and indentation changes, and `ic_fluent_cube_quick_24_filled.svg` is untracked. Neither should be swept into the feature-removal commit.

---

## 4. Decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| kubectl version | **v1.37.2** | Current stable; supports clusters 1.36–1.38 |
| Helm version | **v4.3.1** | Current stable; matches the feature's previous "latest" behavior. Helm 3.22.1 can be selected manually; security support ends 2027-02-10 |
| Minikube | **Removed entirely** | Explicitly not needed |
| Verification | **Hardcoded per-arch SHA256 digests** | Reproducible, fail-closed, no GPG/keyserver/GitHub dependency |
| Completion | **Preserve** | Add `bash-completion`; keep the kubectl block; add a separate Helm completion block |
| Version source of truth | **Dockerfile ARGs** | No `build.args`; follows the existing "bump the ARG" pattern |
| Commit shape | **3 commits** | Preserve pre-existing bumps; feature removal; separate stale-docs refresh |

### Official digests used by this plan

| Artifact | Architecture | SHA256 |
| --- | --- | --- |
| kubectl v1.37.2 | amd64 | `c04487523e7aa7d1493f7808174c899db93d7a9cf57531420cd76b9bd415f8f4` |
| kubectl v1.37.2 | arm64 | `fcc16f63186659d9722014b7e02d5fdd2d4e669cb8c0ab66365d7d3b8ba03509` |
| Helm v4.3.1 | amd64 | `0403a88ae20913d11b10a2467b50087721fea7581736da6b9d3992f5357fe54b` |
| Helm v4.3.1 | arm64 | `8cf8f66ecbc252ac8f7f06cca68aba88508ddfde3a6a34feb1678ad1694b4f88` |

Source URLs to record in Dockerfile comments:

- `https://dl.k8s.io/release/v1.37.2/bin/linux/amd64/kubectl.sha256`
- `https://dl.k8s.io/release/v1.37.2/bin/linux/arm64/kubectl.sha256`
- `https://get.helm.sh/helm-v4.3.1-linux-amd64.tar.gz.sha256sum`
- `https://get.helm.sh/helm-v4.3.1-linux-arm64.tar.gz.sha256sum`

---

## 5. Implementation plan

### Step 0 — Baseline and safety net

**Actions**

```bash
git switch -c feature/remove-kubectl-helm-minikube
git tag pre-kubectl-helm-pin
git status --porcelain
docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | head
cp .devcontainer/devcontainer-lock.json "$TMPDIR/devcontainer-lock.json.pre-removal"
```

Record the previous image ID and current versions:

- kubectl `v1.37.2`
- Helm `v4.3.1`
- minikube `v1.39.0`

**Acceptance**

- Baseline tag and lockfile backup exist.
- The untracked SVG remains untracked and is explicitly excluded from all commits.

---

### Step 1 — Commit 1: preserve pre-existing bumps and fix the yq assertion

**Edits**

- Stage only the existing Dockerfile version-bump/indentation hunks with `git add -p`.
- In `test/devcontainer-smoke.sh`, replace the hardcoded yq check:

  ```bash
  check "run: yq version" bash -c "yq --version | grep -q 'v4.54.1'"
  ```

  with a value derived from `/workspace/.devcontainer/Dockerfile`:

  ```bash
  yq_expected="$(sed -n 's/^ARG YQ_VERSION=//p' /workspace/.devcontainer/Dockerfile | head -1 | tr -d '"')"
  check "run: yq version" bash -c "yq --version | grep -qF '$yq_expected'"
  ```

- Update the README note that says the runtime smoke test hardcodes yq `v4.54.1`; it now derives the value from the Dockerfile.
- Do not update the stale yq/OpenCode/Spec Kit version rows yet.

**Validation**

```bash
test/devcontainer-smoke.sh static
```

**Acceptance**

- `static` passes.
- The Dockerfile bumps are committed without reverting or mixing in feature-removal work.
- The SVG is not staged.

---

### Step 2 — Dockerfile install block

**File:** `.devcontainer/Dockerfile`

#### 2.1 Add ARGs and digest constants

Place with the existing pins near the top. Add comments with the official checksum source URLs.

```dockerfile
# kubectl: https://dl.k8s.io/release/v1.37.2/bin/linux/{amd64,arm64}/kubectl.sha256
# Helm:   https://get.helm.sh/helm-v4.3.1-linux-{amd64,arm64}.tar.gz.sha256sum
ARG KUBECTL_VERSION=v1.37.2
ARG KUBECTL_SHA256_AMD64=c04487523e7aa7d1493f7808174c899db93d7a9cf57531420cd76b9bd415f8f4
ARG KUBECTL_SHA256_ARM64=fcc16f63186659d9722014b7e02d5fdd2d4e669cb8c0ab66365d7d3b8ba03509
ARG HELM_VERSION=v4.3.1
ARG HELM_SHA256_AMD64=0403a88ae20913d11b10a2467b50087721fea7581736da6b9d3992f5357fe54b
ARG HELM_SHA256_ARM64=8cf8f66ecbc252ac8f7f06cca68aba88508ddfde3a6a34feb1678ad1694b4f88
```

#### 2.2 Add `bash-completion`

Add `bash-completion` to the existing `apt-get install` package list. Do not add `gnupg2` or `dirmngr`; the digest model does not need them.

#### 2.3 Add the root install block

Place it **after** the Spec Kit install and **before** `USER $USERNAME`.

```dockerfile
# Install kubectl and Helm from official release artifacts. Digests are pinned
# per architecture in the ARGs above; source URLs are recorded with the ARGs.
RUN set -eu; \
  arch="$(dpkg --print-architecture)"; \
  case "$arch" in \
    amd64) kubectl_sha256="${KUBECTL_SHA256_AMD64}"; helm_sha256="${HELM_SHA256_AMD64}" ;; \
    arm64) kubectl_sha256="${KUBECTL_SHA256_ARM64}"; helm_sha256="${HELM_SHA256_ARM64}" ;; \
    *) echo "Unsupported architecture for kubectl/Helm: $arch" >&2; exit 1 ;; \
  esac; \
  tmp="$(mktemp -d)"; \
  trap 'rm -rf "$tmp"' 0; \
  curl -fsSL --retry 3 --retry-delay 2 --retry-connrefused \
    -o "$tmp/kubectl" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${arch}/kubectl"; \
  printf '%s  kubectl\n' "$kubectl_sha256" | (cd "$tmp" && sha256sum --strict -c -); \
  install -m 0755 "$tmp/kubectl" /usr/local/bin/kubectl; \
  helm_asset="helm-${HELM_VERSION}-linux-${arch}.tar.gz"; \
  curl -fsSL --retry 3 --retry-delay 2 --retry-connrefused \
    -o "$tmp/$helm_asset" "https://get.helm.sh/$helm_asset"; \
  printf '%s  %s\n' "$helm_sha256" "$helm_asset" | (cd "$tmp" && sha256sum --strict -c -); \
  tar -xzf "$tmp/$helm_asset" -C "$tmp"; \
  install -m 0755 "$tmp/linux-${arch}/helm" /usr/local/bin/helm; \
  kubectl version --client; \
  helm version --template '{{.Version}}'; \
  echo
```

> **Do not validate runtime versions yet.** The still-enabled feature installs after the Dockerfile and overwrites `/usr/local/bin/kubectl` and `/usr/local/bin/helm`.

**Acceptance**

- `bash-completion` is in the apt block.
- Both digest pairs are present and 64-character lowercase hex.
- The block uses `sha256sum --strict -c -`, canonical Helm tarball names, and the architecture fail-fast.
- Static checks for ARGs/URLs/checksum patterns pass.

---

### Step 3 — Remove the feature and regenerate the lockfile

**File:** `.devcontainer/devcontainer.json`

Delete:

```json
"ghcr.io/devcontainers/features/kubectl-helm-minikube:1": {}
```

Leave every other feature, mount, env, and lifecycle hook unchanged.

#### Lockfile procedure

1. Run an unfrozen build:

   ```bash
   devcontainer build --workspace-folder .
   ```

   This validates the new Dockerfile block and gives the CLI a chance to update the lockfile.

2. Inspect:

   ```bash
   git diff -- .devcontainer/devcontainer-lock.json
   ```

   Expected diff: removal of only `ghcr.io/devcontainers/features/kubectl-helm-minikube:1`.

3. If unrelated entries churn:

   ```bash
   cp "$TMPDIR/devcontainer-lock.json.pre-removal" .devcontainer/devcontainer-lock.json
   ```

   Then deterministically remove only the feature entry:

   ```bash
   python3 - <<'PY'
   import json, pathlib
   p = pathlib.Path('.devcontainer/devcontainer-lock.json')
   d = json.loads(p.read_text())
   d['features'].pop('ghcr.io/devcontainers/features/kubectl-helm-minikube:1', None)
   p.write_text(json.dumps(d, indent=2) + '\n')
   PY
   ```

   This is the documented, conscious exception to the README's "do not edit the lockfile by hand" guidance.

4. Validate:

   ```bash
   test/devcontainer-smoke.sh static
   devcontainer build --workspace-folder . --frozen-lockfile
   ```

**Acceptance**

- Build succeeds with the feature removed.
- Lockfile contains no `kubectl-helm-minikube` key.
- All other lockfile entries are byte-identical to the backup.
- `static` and frozen build pass.
- The backup is retained until final validation, then removed.

---

### Step 4 — Update `post-create.sh`

**File:** `.devcontainer/post-create.sh`

1. Keep the existing `# --- kubectl aliases ---` block unchanged.
2. Add a separate block after it, before the verification section:

   ```bash
   echo "Setting up Helm completion..."
   if ! grep -qF '# --- helm completion ---' "$HOME/.bashrc" 2>/dev/null; then
     cat >>"$HOME/.bashrc" <<'EOF'

   # --- helm completion ---
   if command -v helm >/dev/null 2>&1; then
     source <(helm completion bash 2>/dev/null)
   fi
   EOF
   fi
   ```

3. Add to the verification section:

   ```bash
   kubectl version --client >/dev/null
   helm version --template '{{.Version}}' >/dev/null
   ```

Do not put the Helm block inside the kubectl marker; idempotency and existing-container upgrades depend on a separate marker.

**Acceptance**

- `bash -n .devcontainer/post-create.sh` passes.
- Static test finds `# --- helm completion ---`.
- Running post-create twice does not duplicate markers or grow `.bashrc` unexpectedly.

---

### Step 5 — Update the smoke tests

**File:** `test/devcontainer-smoke.sh`

#### Static test

- Keep the feature/lock set-equality check.
- Add explicit absence checks for `kubectl-helm-minikube` in both `features` and the lockfile.
- Add `bash-completion` to the apt-package assertion, scoped to the apt `RUN` block.
- Extend the ARG loop with `KUBECTL_VERSION`, `HELM_VERSION`, and all four digest ARGs, using anchored regexes:

  ```python
  re.search(rf'^ARG {re.escape(arg)}=\S+', dockerfile, re.M)
  ```

- Assert digest ARGs match `[0-9a-f]{64}`.
- Assert the official URLs contain `${KUBECTL_VERSION}` / `${HELM_VERSION}` and `${arch}`.
- Assert the block uses `sha256sum --strict -c -` and synthetic `printf` lines.
- Assert `post-create.sh` contains `# --- helm completion ---`, `helm completion bash`, `kubectl version --client`, and `helm version --template '{{.Version}}'`.
- Update the line-6 comment that uses `minikube-config` as the feature-volume example.

#### `run_pre_smoke`

- Remove `minikube` from the command list.
- Add version parsing from `/workspace/.devcontainer/Dockerfile`:

  ```bash
  arg() { sed -n "s/^ARG $1=//p" /workspace/.devcontainer/Dockerfile | head -1 | tr -d '"'; }
  kubectl_expected="$(arg KUBECTL_VERSION)"
  helm_expected="$(arg HELM_VERSION)"
  ```

- Assert exact versions:

  ```bash
  check_eq "kubectl version" "$kubectl_expected" \
    "$(kubectl version --client -o json | python3 -c 'import json,sys; print(json.load(sys.stdin)["clientVersion"]["gitVersion"])')"
  check_eq "helm version" "$helm_expected" \
    "$(helm version --template '{{.Version}}')"
  ```

- Add:

  ```bash
  check "minikube absent" bash -c '! command -v minikube'
  check "package: bash-completion" dpkg -s bash-completion
  ```

#### `run_smoke`

- Remove `minikube` from the command list and delete `minikube version`.
- Repeat the exact version and minikube-absence checks.
- Add:

  ```bash
  check "bashrc: helm completion" grep -q '# --- helm completion ---' "$HOME/.bashrc"
  check "bash-completion: _init_completion" bash -ic 'declare -F _init_completion'
  check "completion: kubectl" bash -ic 'complete -p kubectl | grep -q __start_kubectl'
  check "completion: helm" bash -ic 'complete -p helm | grep -q __start_helm'
  ```

- Keep the yq derivation from Step 1.

**Acceptance**

- `test/devcontainer-smoke.sh static` passes.
- `pre` proves image-level kubectl/Helm versions with no post-create.
- `up` proves runtime versions, Helm completion, and minikube absence.
- `idempotent` passes.

---

### Step 6 — Update the README

**File:** `README.md`

#### Feature-removal commit (Commit 2)

Update only kubectl/Helm-related content plus the specified rows/notes:

- Overview "Cloud-native tooling" bullet: remove minikube.
- "Comfortable shell" bullet: add Helm completion.
- What's included → Kubernetes row: remove minikube; keep kubectl, Helm, kind, kubectx/kubens.
- Shell row: add Helm completion.
- Pinned build-time tools table: add kubectl `v1.37.2` and Helm `v4.3.1` rows.
- Pinned-tools parenthetical note: add kubectl and Helm.
- Prerequisites architecture note: include kubectl/Helm in the amd64/arm64 fail-fast statement.
- Design notes:
  - Why the feature was removed: no minikube, exact pins, digest verification, and the feature's Copilot customization is intentionally dropped.
  - Trust model: official artifacts, hardcoded per-arch digests, source URLs in Dockerfile comments, `sha256sum --strict`; the repository is the trust anchor, not a same-origin checksum.
  - Helm 4.3.1 default; Helm 3.22.1 can be selected by editing `HELM_VERSION` and its digest ARGs; Helm 3 security support ends 2027-02-10.
  - Helm 4.3.x supports Kubernetes 1.34–1.37; kubectl 1.37.2 supports 1.36–1.38. These are separate policies.
  - Minikube removed; `kind` remains the in-repo local-cluster option. Re-add the feature or install minikube manually if needed.
  - Old containers retain the feature's binaries until recreated; `smoke-real` will fail the new negative assertions on them.
  - The feature's transitive `gnupg2`/`dirmngr`/`jq` guarantees are gone; add them explicitly if a project needs GPG or jq.
- Change tool versions section: note that kubectl/Helm version bumps require updating the matching digest ARGs, and tests derive expected versions from the Dockerfile.
- Troubleshooting lockfile section: document the manual single-entry removal as a conscious fallback when CLI regeneration churns unrelated entries.

#### Separate docs commit (Commit 3)

Refresh only the stale version rows:

- Badge: OpenCode `2.2.5` → `2.2.6`.
- AI/workflow row: OpenCode `2.2.6`, Spec Kit `v1.3.2`.
- Pinned-tools table: yq `v4.54.3`, OpenCode `2.2.6`, Spec Kit `v1.3.2`.

**Acceptance**

- Commit 2 contains no stale yq/OpenCode/Spec Kit version-row changes.
- Commit 3 contains no kubectl/Helm/feature-removal changes.
- A final `grep` for `v4.54.1`, `2.2.5`, and `0.16.4` in `README.md` returns nothing.

---

## 6. Validation gates

Run in this order. Stop at the first failure.

| Gate | Command | Pass criteria |
| --- | --- | --- |
| Static | `test/devcontainer-smoke.sh guard`<br>`test/devcontainer-smoke.sh static` | All checks pass; no feature/lock mismatch; no malformed ARG/digest |
| Lockfile | `git diff -- .devcontainer/devcontainer-lock.json` | Only the feature entry removed, or documented manual fallback used |
| Frozen build | `test/devcontainer-smoke.sh build` | Static + `devcontainer build --frozen-lockfile` succeed |
| Image-level | `test/devcontainer-smoke.sh pre` | kubectl/Helm exact versions, minikube absent, bash-completion installed, all other tools present |
| Runtime | `test/devcontainer-smoke.sh up` | Runtime versions, post-create, Helm completion, kubectl completion, minikube absent |
| Idempotency | `test/devcontainer-smoke.sh idempotent` | `.bashrc` line count and marker count unchanged after two post-create runs |
| Recreate | `test/devcontainer-smoke.sh recreate` | New container passes runtime smoke with persistent volumes |
| Fresh volumes | `test/devcontainer-smoke.sh fresh` | Volumes removed, container recreated, runtime smoke passes |
| Full pass | `test/devcontainer-smoke.sh all` | Optional if time permits; repeats the above plus PTY paste |
| Cleanup | `test/devcontainer-smoke.sh cleanup` | Disposable copy/container/test volumes removed |

Additional gates:

```bash
devcontainer read-configuration --workspace-folder . --include-merged-configuration
```

Parse the merged configuration and assert:

- no `kubectl-helm-minikube` feature,
- no `minikube-config` mount,
- no `github.copilot.chat.codeGeneration.instructions` entry from the feature.

Manual checks:

```bash
devcontainer exec --workspace-folder . bash -lc '
  kubectl version --client
  helm version --template "{{.Version}}"
  ! command -v minikube
  bash -ic "declare -F _init_completion; complete -p kubectl; complete -p helm"
'
```

- Verify interactive Tab completion for `kubectl` and `helm`.
- Verify `helm registry login` still behaves as before when a GitHub token is present.
- Optional multi-arch gate: `devcontainer build --workspace-folder . --platform linux/arm64` on an amd64 host (or the reverse). Record whether it was run; if not, state it as residual risk.

---

## 7. Rollout

1. Rebuild existing containers:

   ```bash
   devcontainer up --workspace-folder . --remove-existing-container
   ```

   In VS Code, use **Rebuild Container**, not just Reopen.

2. Confirm the new container:
   - kubectl `v1.37.2`,
   - Helm `v4.3.1`,
   - `command -v minikube` fails,
   - kubectl and Helm completion work.

3. Check the old global volume before removing it:

   ```bash
   docker ps -a --filter volume=minikube-config
   ```

   Remove only when no container uses it. The volume name is global to the Docker daemon and may be shared by other projects using this base.

4. Document in the PR/release notes:
   - old containers retain minikube until recreated;
   - `smoke-real` on an old container is expected to fail the new assertions;
   - `kind` remains the local-cluster option;
   - minikube can be re-added as a feature if needed.

---

## 8. Rollback

- Keep the `pre-kubectl-helm-pin` tag and the previous image ID.
- If Commit 2 fails validation:

  ```bash
  git revert <commit-2-sha>
  ```

  This restores the feature entry, Dockerfile state, lockfile, post-create, tests, and docs. Rebuild and run `static`, `build`, and `up`.

- If only Commit 3 fails, revert Commit 3; no image rebuild needed.
- If the lockfile was manually edited, keep the backup until the rollback is validated; the revert should restore the feature entry, but compare against the backup.
- Do not remove the `minikube-config` volume until the new setup has passed final validation. Volume removal is irreversible.
- Existing old containers remain usable as a fallback while the new image is being validated.

---

## 9. Residual risks

- **Digest maintenance:** every kubectl/Helm bump requires updating the version ARG and the matching per-arch digest ARGs. A mismatch fails the build closed, which is good, but the maintainer must fetch the official values. Renovate/Dependabot will not reliably update custom digest ARGs.
- **Provenance:** hardcoded digests pin bytes, not build provenance. The previous feature performed Helm GPG verification (with a moving `KEYS` source); this build performs no GPG or cosign check. The initial digest capture was trust-on-first-use over TLS. Cross-check future digests against Helm's signed checksum/release artifacts or kubectl's cosign/sigstore artifacts.
- **Cluster skew:** kubectl 1.37.2 covers 1.36–1.38; Helm 4.3.x covers 1.34–1.37. Users outside those ranges must change both version and digest, and possibly choose a different Helm minor.
- **Multi-arch:** the Dockerfile has explicit amd64/arm64 branches, but the smoke suite normally tests only the host architecture unless the optional `--platform` gate is run.
- **Completion:** explicit sourcing is reliable in this repo because Debian's skel `.bashrc` loads bash-completion. Custom dotfiles can still break it; the new runtime assertions catch regressions in this repo, not user overrides.
- **Lockfile:** CLI regeneration can churn unrelated feature entries. The deterministic single-entry removal is a documented exception and must be validated with `--frozen-lockfile`.
- **Dropped feature side effects:** the Copilot setting and the feature's `gnupg2`/`dirmngr` installs (plus its conditional `jq` install) are gone. Add them explicitly if needed.
- **Reproducibility:** the base image is still `debian:bookworm-slim` without a digest pin, so this change improves tool pinning but does not make the whole image byte-reproducible.
- **Old containers:** `smoke-real` will report false failures against pre-change containers. This is intentional and documented.
- **Optional hardening not applied:** add `--proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 300` to both curl calls, validate the version ARGs against `^v[0-9]+\.[0-9]+\.[0-9]+$`, and consider `tar --no-same-owner` / `install -o root -g root`. These are defense-in-depth; the validated build already pins and verifies digests. Treat `--build-arg` overrides as trusted inputs.

---

## 10. Implementation checklist

- [x] Commit 1 preserves the working-tree bumps and fixes the yq assertion.
- [x] Commit 2 removes the feature, adds the digest-verified install block, updates post-create/tests/docs, and updates the lockfile.
- [x] Commit 3 refreshes only the stale yq/OpenCode/Spec Kit README rows.
- [x] Validation gates pass in order, ending with `read-configuration`, manual completion checks, and `cleanup`.
- [x] Rollout uses `--remove-existing-container`; the global volume is removed only after confirmation.
- [x] Residual risks above are accepted.

---

## 11. References

- [Install and Set Up kubectl on Linux](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)
- [Changing The Kubernetes Package Repository](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/change-package-repository/)
- [Installing Helm](https://helm.sh/docs/intro/install/)
- [Helm 3 End of Life](https://helm.sh/blog/helm-v3-end-of-life/)
- [Verify Signed Kubernetes Artifacts](https://kubernetes.io/docs/tasks/administer-cluster/verify-signed-artifacts/) — optional stronger verification using cosign
- [devcontainers/features kubectl-helm-minikube source](https://github.com/devcontainers/features/tree/main/src/kubectl-helm-minikube)
