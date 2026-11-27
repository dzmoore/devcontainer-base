# Proposal

## Why

The devcontainer image currently gets Node.js from `ghcr.io/devcontainers/features/node:1`, which resolves nvm and Node versions at build time and keeps the runtime outside the repository's Dockerfile. The user wants toolchain installs moved into the image gradually, starting with Node installed through nvm, while keeping devcontainers for lifecycle, mounts, the host overlay, and Docker-in-Docker. OpenSpec currently depends on that feature twice: it is installed with npm in `post-create.sh`, so the spec layer breaks if Node changes or the container starts without network access.

## What Changes

- Install nvm `v0.41.0` and Node.js `26.13.1` as the `developer` user in `.devcontainer/Dockerfile`, verifying the nvm install script against a pinned SHA-256 and disabling nvm's source-build fallback.
- Put `$NVM_DIR/current/bin` on the image `PATH` and add `/etc/profile.d/00-nvm.sh`, `/etc/bash.bashrc`, and `~/.bashrc` snippets so `node`, `npm`, and `npx` resolve in non-interactive, login, and interactive shells.
- Add `make`, `gcc`, `g++`, and `libc6-dev` to the apt package list to retain the node-gyp build capability that the Node feature supplied.
- Install OpenSpec `2.1.1` from the standalone release tarball into `/usr/local/bin`, with per-architecture SHA-256 pins, so the CLI no longer depends on the nvm-managed Node version.
- Remove the Node feature from `.devcontainer/devcontainer.json` and `.devcontainer/devcontainer-lock.json`.
- Remove the npm install, Node version guard, and OpenSpec version guard from `.devcontainer/post-create.sh`; keep the OpenSpec verification and telemetry opt-out.
- **BREAKING**: pnpm is no longer preinstalled. The Node feature installed it unconditionally; no manifest, lockfile, script, or host configuration in this repository uses it. The migration note documents `npm install -g pnpm` for anyone who needs it.
- Add static contract assertions and update the focused smoke suites, README, and a migration note.

## Capabilities

### New Capabilities

- `node-toolchain`: Node.js is provisioned by a pinned, checksum-verified nvm install in the image and is usable by the developer user in non-interactive and login shells, with global npm installs working without sudo.

### Modified Capabilities

- `spec-artifacts`: Additional requirement only; no existing requirement changes. The OpenSpec CLI is provided by a pinned standalone binary in the image instead of an npm install in `post-create.sh`, so its availability does not depend on the Node version.

## Impact

- `.devcontainer/Dockerfile`, `.devcontainer/devcontainer.json`, `.devcontainer/devcontainer-lock.json`, `.devcontainer/post-create.sh`
- `test/devcontainer-smoke.sh`, `test/openspec-smoke.sh`, `test/docs-smoke.sh`
- `README.md`, `docs/migrations/2026-11-21-node-nvm.md`
- Image size and build time increase; pnpm is removed; the other nine devcontainer features and Docker-in-Docker stay unchanged.
- Existing containers keep their old toolchain until they are rebuilt.
