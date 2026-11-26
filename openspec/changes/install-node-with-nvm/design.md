# Design

## Context

See `proposal.md` for motivation. Today `ghcr.io/devcontainers/features/node:1` (resolved 1.7.1) installs nvm under `/usr/local/share/nvm`, resolves Node `26.13.1` at build time, installs pnpm unconditionally, and exports `NVM_DIR`, `NVM_SYMLINK_CURRENT`, and a `current/bin` PATH entry as feature `containerEnv`. `post-create.sh` then installs `@fission-ai/openspec@2.1.1` with npm and enforces Node `>=22.20.0` and OpenSpec `2.1.1` with shell guards.

A throwaway image validated the per-user nvm pattern on this host: nvm `0.41.0`, Node `26.13.1`, `sh -c`, `bash -c`, `sh -lc`, and `bash -lc` all resolved `node`; `nvm --version` worked in a login shell; `npm install -g degit` worked as `developer`; and the pattern survived a simulated UID remap plus home-directory chown. That spike also showed that a `PATH` entry alone covers non-interactive shells, while `/etc/profile.d` is required for login shells.

The research notes are copied at `research/2026-11-21-nvm-in-dockerfile/` for this worktree. They confirm `NVM_NO_SOURCE_FALLBACK=1`, `PROFILE=/dev/null`, `NVM_SYMLINK_CURRENT`, and the install-script behavior. The nvm `v0.41.0` installer digest was rechecked on 2026-11-21: `045932fe05f0d4247c946f2ec0ec4026dbfd8ce88a5f67ea28d8ea833227f48b`.

The OpenSpec `v2.1.1` release assets `openspec-linux-x64.tar.gz` and `openspec-linux-arm64.tar.gz` exist and match the published `SHA256SUMS` (read 2026-11-21):

| Asset | SHA-256 |
| --- | --- |
| `openspec-linux-x64.tar.gz` | `22f0c7c96cc14138becb42aa98e589050c94cda793cbefd7e7ac2d7dee78b6d5` |
| `openspec-linux-arm64.tar.gz` | `b7ab16e4138e88df2d2ddc13e687bf20f6fe22751db68492d48e00d77b0183da` |

The `devcontainer` CLI is not installed in this environment. Docker 29.10.0 is available, so the runtime evidence must come from a direct `docker build` plus `docker run`, not the existing `build`/`up`/`smoke` modes.

## Goals / Non-Goals

**Goals:**

- Provision Node.js from a pinned nvm release in the Dockerfile, as the `developer` user, with checksum verification.
- Make `node`, `npm`, and `npx` resolve in non-interactive, login, and interactive shells, and make `nvm` available in bash shells.
- Decouple OpenSpec from Node by installing the pinned standalone binary in the image.
- Remove the Node feature while keeping every other feature and the devcontainer lifecycle unchanged.
- Leave the repository with static contract tests, a Docker-only runtime matrix, and a migration note.

**Non-Goals:**

- Moving Go, Python, GitHub CLI, kind, kubectx/kubens, fzf, uv, or Bun out of devcontainer features. Those are later phases.
- Removing devcontainers or Docker-in-Docker.
- Adding a feature allowlist that rejects new features. That is a later hardening step.
- Replacing nvm with fnm, mise, Volta, or asdf. Research found no material advantage strong enough to override the user's request, and fnm provides no checksum verification today.
- Proving a failed Node download through a live negative build. The flag is verified statically and against the upstream documentation; failure injection would need a mutable mirror build arg.

## Decisions

### Decision: Install nvm per-user under `/home/developer/.nvm`

The image declares the nvm environment before the install:

```dockerfile
ARG USERNAME=developer
ENV HOME=/home/${USERNAME}
ENV NVM_DIR=/home/${USERNAME}/.nvm
ENV NVM_SYMLINK_CURRENT=true
```

The install runs as `developer` with `PROFILE=/dev/null`, so the installer does not edit any profile file. The developer user owns the Node tree, so `npm install -g` writes under `$NVM_DIR/current` with no sudo, no group, and no `chmod -R g+rw` follow-up. `post-create.sh` adds `$HOME/.nvm` to its existing recursive ownership repair so a remapped container UID can still write the tree even if the devcontainer CLI's home chown is narrower than expected.

`NVM_DIR`, `HOME`, and `NVM_SYMLINK_CURRENT` are persistent image `ENV` values, not build-only locals. `ENV PATH="$NVM_DIR/current/bin:$PATH"` is declared after `ENV NVM_DIR`, so Docker expands the variable; the static test also asserts the resolved literal path.

Alternative: replicate the Node feature's system-wide `/usr/local/share/nvm`. It requires a shared group, setgid directories, and a recursive group-write fix after every install, and the UID remap problem remains because the tree is outside `$HOME`.

### Decision: Pin nvm `v0.41.0` and Node.js `26.13.1`

`v0.41.0` is the current nvm release and contains the 2026 security fixes; older nvm releases are unsupported and carry known advisories. `26.13.1` is the Active LTS release, matches what the Node feature currently resolves, includes the November 2026 security fixes, and satisfies OpenSpec's Node `>=22.20.0` requirement.

The install downloads `https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh`, verifies the installer against SHA-256 `045932fe05f0d4247c946f2ec0ec4026dbfd8ce88a5f67ea28d8ea833227f48b`, and runs it with `PROFILE=/dev/null bash /tmp/nvm-install.sh`. The installer clones the tagged nvm repository; the checksum authenticates the installer text, not the cloned payload. This is a narrower trust claim than the kubectl/Helm digest pattern, and the README trust-anchor note must say so for nvm.

Alternative: pin an older nvm for reproducibility. Rejected because only the newest nvm release is supported. Alternative: clone the signed tag and run `git verify-tag`. Stronger provenance, but it adds a different build-cache shape and the repository already uses pinned, checksum-verified downloads for Glow, kubectl, Helm, and OpenSpec.

### Decision: Fail the build instead of compiling Node

The install runs `NVM_NO_SOURCE_FALLBACK=1 nvm install "$NODE_VERSION"`. Without it, a transient binary download failure can silently turn a short build into a multi-hour source compile, especially under arm64 emulation. The exact variable name and behavior are documented in the nvm `v0.41.0` README and confirmed in the research notes.

### Decision: Expose Node through `PATH` plus profile files

After the install, the image sets `ENV PATH="$NVM_DIR/current/bin:$PATH"`. That covers `sh -c`, `bash -c`, `sh -lc`, `bash -lc`, and the string-form `postCreateCommand`, because none of them needs to source nvm. `nvm install` activates the version, `nvm alias default` records it, and `nvm use default` creates the `current` symlink while `NVM_SYMLINK_CURRENT=true`.

The image also writes:

- `/etc/profile.d/00-nvm.sh` for login shells: `NVM_DIR`, the `current/bin` PATH entry, and a guarded `nvm.sh` source for bash;
- a guarded nvm source block in `/etc/bash.bashrc` and `/home/developer/.bashrc` for interactive bash.

The guard is `type nvm >/dev/null 2>&1 ||`, so an interactive login shell that already sourced nvm through profile.d does not source it twice. Every source uses `nvm.sh --no-use` so an `.nvmrc` naming an uninstalled version does not return status 3 under `set -e`. That also disables nvm's `.nvmrc` auto-switching in interactive shells; developers use an explicit `nvm use` instead. `NVM_SYMLINK_CURRENT` stays exported at runtime, so an interactive `nvm use` repoints `current` for every non-interactive consumer.

The `devcontainer.json` `remoteEnv.PATH` stays unchanged: `${containerEnv:PATH}` already inherits the image environment.

Alternative: `BASH_ENV` from nvm's Docker documentation. It is bash-only and does not cover the `/bin/sh -c` lifecycle path, so it fails the `postCreateCommand` requirement.

### Decision: Run the nvm install under bash

Bookworm's `/bin/sh` is dash, and `nvm.sh` is bash-only. The Dockerfile adds `SHELL ["/bin/bash", "-c"]` immediately before the user-level install section and keeps it for the remaining build steps. The existing later `RUN` instructions are POSIX-compatible, so the switch is safe.

Alternative: wrap only the nvm `RUN` in `bash -c`. It works but makes a long multi-line instruction harder to read and easy to break on the next edit.

### Decision: Install OpenSpec from the standalone release

The Dockerfile installs `openspec-linux-x64.tar.gz` or `openspec-linux-arm64.tar.gz` from `https://github.com/Fission-AI/OpenSpec/releases/download/${OPENSPEC_VERSION}`, verifies the per-architecture SHA-256 from the table above, extracts `openspec`, installs it to `/usr/local/bin`, and runs the version check with telemetry explicitly disabled:

```sh
env OPENSPEC_TELEMETRY=0 DO_NOT_TRACK=1 openspec --version
```

The checksums are pinned as ARGs. This removes the npm dependency, avoids a network install during container creation, and keeps the CLI working when the nvm default Node changes.

`post-create.sh` keeps a strict `openspec --version` check for `2.1.1` and keeps the telemetry opt-out. It no longer defines `version_ge`, `require_node_version`, or `require_openspec_version`, and it does not run npm, curl, or Node on the OpenSpec path.

### Decision: Remove the Node feature, keep the rest, drop pnpm

`devcontainer.json` and `devcontainer-lock.json` lose only `ghcr.io/devcontainers/features/node:1`. Docker-in-Docker, Go, Python, GitHub CLI, kind, kubectx/kubens, fzf, uv, and Bun remain features. `make`, `gcc`, `g++`, and `libc6-dev` join the apt list to preserve the node-gyp toolchain, including headers, under `--no-install-recommends`. pnpm is dropped because no manifest, lockfile, script, or host configuration in this repository uses it; the migration note gives `npm install -g pnpm` as the replacement.

### Decision: Prove behavior with a Docker-only matrix

Because the `devcontainer` CLI is unavailable, the runtime evidence comes from:

```bash
docker build -t devcontainer-base:nvm-test .devcontainer
```

Then, inside `docker run --rm` with a clean environment:

- `env -i HOME=/home/developer PATH=/usr/local/bin:/usr/bin:/bin sh -c 'node --version && npm --version && npx --version'`
- the same for `bash -c`, `sh -lc`, and `bash -lc`;
- `bash -ic 'nvm --version' </dev/null`;
- exact `node --version` equal to the Dockerfile `NODE_VERSION` and `nvm --version` equal to `NVM_VERSION`;
- `npm prefix -g` and `npm root -g` resolve under `$NVM_DIR/versions/node/v26.13.1`;
- `npm install -g` of a locally packed tarball succeeds without sudo as `developer`;
- a minimal `node-gyp` addon build succeeds;
- `pnpm` is absent;
- `env -i PATH=/usr/local/bin:/usr/bin:/bin openspec --version` reports `2.1.1`;
- a remapped-UID simulation chowns `/home/developer` to `1001:1001`, runs as `setpriv --reuid=1001 --regid=1001 --clear-groups`, and repeats `node --version` and `npm install -g`.

The existing `test/devcontainer-smoke.sh static` remains the fast gate and must assert every static pin, the feature removal, the profile blocks, the apt packages, the post-create removals, and the docs claims.

## Risks / Trade-offs

- **`$NVM_DIR/current` is mutable.** `NVM_SYMLINK_CURRENT` stays exported, so an interactive `nvm use` or `nvm install` repoints `node` for every non-interactive consumer. → Document the behavior; static tests assert the pins; a later change can switch PATH to the concrete version directory.
- **`.nvmrc` auto-switching is disabled.** `--no-use` avoids status 3 under `set -e`. → Document explicit `nvm use`; this is a deliberate behavior change from a stock nvm shell.
- **UID remap ownership.** `post-create.sh` now chowns `$HOME/.nvm` with the other runtime directories, and the Docker-only matrix exercises a `1001:1001` remap. → If the real devcontainer chown differs, the runtime test still proves the tree is writable after the repair.
- **nvm installer integrity is installer-level, not payload-level.** The SHA-256 pin prevents installer drift; the cloned nvm tree and the Node tarball checksum still come from GitHub/nodejs.org. → Narrow the README trust-anchor claim for nvm and record the residual risk.
- **Image size and build time grow.** The image now contains a Node distribution and nvm, while the feature layer is removed. → Accept for Phase 1; measure the built image and note it in the migration report.
- **`SHELL ["/bin/bash", "-c"]` changes later `RUN` semantics.** → Keep the remaining instructions POSIX-compatible and verify a full image build.
- **pnpm disappears without a manifest signal.** → Name it as breaking in the proposal, README, and migration note.
- **The arm64 OpenSpec checksum is not exercised by the amd64 build.** → The release assets and `SHA256SUMS` were verified; the Dockerfile fails closed on a mismatch.
- **Build-time OpenSpec telemetry.** → The version check runs with `OPENSPEC_TELEMETRY=0` and `DO_NOT_TRACK=1`, so `docker build` does not emit an event or create root-owned config state.

## Migration Plan

1. Rebuild the devcontainer from the updated repository; existing containers keep the old feature-based toolchain until recreated.
2. Verify `node --version` reports `26.13.1`, `nvm --version` reports `0.41.0`, and `openspec --version` reports `2.1.1`.
3. If a project needs pnpm, run `npm install -g pnpm`; it installs under `$NVM_DIR/current`.
4. Roll back by reverting the change and rebuilding; the Node feature returns with its previous lock entry.

## Open Questions

None blocking. A future change can replace the `current` symlink with a concrete version directory and add a feature allowlist.
