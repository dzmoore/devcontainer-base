<div align="center">

<img src="https://containers.dev/img/devcontainers-logo.png" alt="Dev Containers" width="96" />

# devcontainer-base

**A batteries-included Dev Container for polyglot, cloud-native, and AI-assisted development.**

[![Dev Containers](https://img.shields.io/badge/Dev_Containers-spec-2753E3?style=flat-square&logo=visualstudiocode&logoColor=white)](https://containers.dev)
[![Debian 12](https://img.shields.io/badge/Debian-12-A81D33?style=flat-square&logo=debian&logoColor=white)](https://www.debian.org)
[![OpenCode](https://img.shields.io/badge/OpenCode-2.2.6-000000?style=flat-square)](https://opencode.ai)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue?style=flat-square)](LICENSE)

[Overview](#overview) • [What's included](#whats-included) • [Quick start](#quick-start) • [Use it in your project](#use-it-in-your-project) • [Configuration](#configuration) • [Testing](#testing) • [Troubleshooting](#troubleshooting)

</div>

A reusable [Dev Container](https://containers.dev) definition that turns a fresh checkout into a ready-to-code Linux environment. It combines a slim Debian base with language runtimes, Docker and Kubernetes tooling, an AI coding agent, spec-driven development tooling, and a tuned shell, so every project and every teammate starts from the same setup.

> [!NOTE]
> This repository is a base configuration, not a published container image. Open it directly to work on the environment itself, or copy `.devcontainer/` into a project that needs it.

## Overview

`devcontainer-base` is made for projects that need more than a single runtime, and for workflows that mix local containers, a Kubernetes cluster, and an AI coding agent in the same workspace. It is a good fit for platform, backend, and AI projects that want a consistent environment without maintaining a bespoke Dockerfile for every repository.

- **Polyglot by default** — Node.js, Bun, Python with uv, and Go are ready to use.
- **Cloud-native tooling** — Docker-in-Docker, Compose, Buildx, kubectl, Helm, kind, and kubectx/kubens.
- **AI-assisted workflow** — OpenCode, GitHub Spec Kit, and persistent tool state.
- **Comfortable shell** — Starship prompt, useful aliases, kubectl and Helm completion, and paste-safe terminal settings.
- **Reproducible** — pinned build-time tools and a Dev Container feature lockfile.
- **Tested** — a smoke suite covers build, runtime, shell paste, idempotency, and volume lifecycle.

## What's included

| Area | Details |
| --- | --- |
| **Base** | `debian:bookworm-slim`, non-root `developer` user (UID/GID 1000 by default), passwordless sudo, `en_US.UTF-8` locale, bash |
| **Languages** | Node.js + npm, Bun, Python 3 + uv, Go |
| **Containers** | Docker-in-Docker, Docker Compose, Buildx |
| **Kubernetes** | kubectl, Helm, kind, kubectx, kubens |
| **CLI tools** | git, GitHub CLI (`gh`), fzf, ripgrep (`rg`), curl, OpenSSH client, unzip, zip, yq |
| **AI & workflow** | OpenCode 2.2.6, Neovim 0.12.6, Starship 1.27.0, GitHub Spec Kit (`specify`) 1.3.2 |
| **Shell** | aliases from `aliases.sh`, a `k` wrapper (`k ns`, `k ctx`, otherwise kubectl), kubectl and Helm completion, bracketed paste, TERM fallback, Starship prompt |
| **Persistence** | named volumes for OpenCode, OpenTUI, uv, Neovim, Kubernetes config, and `/worktrees` |

> [!NOTE]
> The upstream tools installed in the Dockerfile (`yq`, kubectl, Helm, OpenCode, Neovim, Starship, and Spec Kit) are pinned with build args. Language runtime versions are provided by Dev Container Features; pin them with feature options if your project needs exact versions. The resolved feature versions are stored in `devcontainer-lock.json`.

### Pinned build-time tools

| Tool | Version |
| --- | --- |
| [yq](https://github.com/mikefarah/yq) | `v4.54.3` |
| [kubectl](https://kubernetes.io/docs/reference/kubectl/) | `v1.37.2` |
| [Helm](https://helm.sh) | `v4.3.1` |
| [OpenCode](https://opencode.ai) | `2.2.6` |
| [Neovim](https://neovim.io) | `v0.12.6` |
| [Starship](https://starship.rs) | `v1.27.0` |
| [GitHub Spec Kit](https://github.com/github/spec-kit) (`specify`) | `v1.3.2` |

### Persistent volumes

Named volumes keep tool state and caches across container rebuilds:

| Volume | Container path | Purpose |
| --- | --- | --- |
| `opencode-share` | `~/.local/share/opencode` | OpenCode data |
| `opencode-state` | `~/.local/state/opencode` | OpenCode state |
| `opentui-cache` | `~/.local/share/opentui` | OpenTUI cache |
| `uv-cache` | `~/.local/share/uv` | uv package cache |
| `nvim-state` | `~/.local/state/nvim` | Neovim state |
| `nvim-share` | `~/.local/share/nvim` | Neovim plugins and data |
| `kubeconfig` | `~/.kube` | Kubernetes config and kind cluster contexts |
| `worktrees` | `/worktrees` | Git worktrees that survive a rebuild |

> [!WARNING]
> The volume names are global to the Docker daemon. Projects using this base share the same state and caches. Rename the `source=` values in `devcontainer.json` if you need per-project isolation. The `kubeconfig` volume contains cluster credentials; rename it per project if the clusters must be isolated.

## Quick start

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (Docker Desktop or Docker Engine)
- One of:
  - [VS Code](https://code.visualstudio.com/) with the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
  - The [Dev Containers CLI](https://github.com/devcontainers/cli): `npm install -g @devcontainers/cli`

> [!NOTE]
> The secret mounts in `devcontainer.json` use `${localEnv:HOME}`. On Windows, use WSL or make sure `HOME` is set in the environment where the Dev Containers tooling runs. The Dockerfile supports `amd64` and `arm64`; the pinned Neovim, yq, kubectl, and Helm downloads fail fast on other architectures.

### Open this repository

Clone the repository and start the container:

```bash
git clone https://github.com/dzmoore/devcontainer-base.git
cd devcontainer-base
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . bash
```

The first build downloads the base image, Dev Container Features, and pinned tools, so it can take several minutes.

In VS Code, open the folder and run **Dev Containers: Reopen in Container** from the command palette.

### Use it in your project

Copy `.devcontainer/` into the project you want to develop:

```bash
git clone --depth 1 https://github.com/dzmoore/devcontainer-base.git /tmp/devcontainer-base
mkdir -p .devcontainer
cp -R /tmp/devcontainer-base/.devcontainer/. .devcontainer/
rm -rf /tmp/devcontainer-base
```

If the project already has a `.devcontainer/`, merge the files instead of overwriting them. Then update the `"name"` in `devcontainer.json` if you like, and reopen the project in the container. The rest of the configuration is self-contained.

> [!TIP]
> If you use [`degit`](https://github.com/Rich-Harris/degit), you can copy just the configuration with `npx degit dzmoore/devcontainer-base/.devcontainer .devcontainer`.

### Optional: host secrets

Two read-only bind mounts make host-side secrets available inside the container:

- `~/.devcontainer/github/.env` provides `GITHUB_TOKEN` for `gh`; `post-create.sh` also uses it to log Helm into `ghcr.io`.
- `~/.devcontainer/brave/.env` provides `BRAVE_API_KEY` to tools that read it, such as Brave Search integrations.

Create the files on the host before the first launch:

```bash
mkdir -p ~/.devcontainer/github ~/.devcontainer/brave
printf 'GITHUB_TOKEN=%s\n' "$GITHUB_TOKEN" > ~/.devcontainer/github/.env
printf 'BRAVE_API_KEY=%s\n' "$BRAVE_API_KEY" > ~/.devcontainer/brave/.env
chmod 600 ~/.devcontainer/github/.env ~/.devcontainer/brave/.env
```

The files are mounted read-only and sourced by interactive bash shells. If you do not need them, remove the corresponding entries from `mounts` in `devcontainer.json`.

> [!IMPORTANT]
> Create the `.env` files before the first launch. When Docker creates a missing bind source itself, it may create a directory instead of a file. If that happens, remove the directory and create the file before starting the container again.

## Configuration

### Files

| Path | Purpose |
| --- | --- |
| `.devcontainer/Dockerfile` | Debian base, non-root user, locale, and pinned CLI tools |
| `.devcontainer/devcontainer.json` | Features, mounts, environment, and lifecycle hooks |
| `.devcontainer/devcontainer-lock.json` | Resolved Dev Container Feature versions |
| `.devcontainer/post-create.sh` | Idempotent setup: env loading, ownership repair, shell hooks, Helm login |
| `.devcontainer/aliases.sh` | Interactive shell aliases |
| `.devcontainer/starship.toml` | Starship prompt configuration |
| `test/devcontainer-smoke.sh` | End-to-end smoke suite |
| `test/paste-smoke.py` | PTY paste regression test |

`devcontainer.json` runs `post-create.sh` as the `postCreateCommand` and waits for it to finish before returning control.

### Change tool versions

Bump the relevant `ARG` at the top of `.devcontainer/Dockerfile`, then rebuild. For kubectl and Helm, update the matching per-architecture `SHA256` digest ARGs in the same change:

```bash
devcontainer build --workspace-folder .
```

To change a Dev Container Feature or its options, edit `features` in `devcontainer.json` and run `devcontainer build` or `devcontainer up`. The CLI updates `devcontainer-lock.json` by default; commit the lockfile. Use `--frozen-lockfile` in CI to fail when the lockfile is out of date.

To rebuild an existing container after a change:

```bash
devcontainer up --workspace-folder . --remove-existing-container
```

> [!NOTE]
> The runtime smoke test derives the expected yq, kubectl, and Helm versions from their `ARG`s in `.devcontainer/Dockerfile`, so the assertions stay in step with the pins automatically.

### Project-local configuration

The config points a few tools at workspace files and keeps the writable Kubernetes config inside the container:

- `KUBECONFIG=/home/developer/.kube/config` — the container-local file lives in the `kubeconfig` volume and is where kind and kubectl write new contexts. It is intentionally the only default path: client-go locks every file in `KUBECONFIG`, and a workspace path on macOS VirtioFS can break `kind`. To use a project kubeconfig at `.kube/config`, merge or copy it manually; see [kind fails with `config.lock: permission denied`](#kind-fails-with-configlock-permission-denied).
- `OPENCODE_CONFIG=/workspace/opencode.jsonc` — add a project-specific OpenCode config at `opencode.jsonc`.
- `STARSHIP_CONFIG=/workspace/.devcontainer/starship.toml` — the prompt config shipped with this base.

Change the `containerEnv` and `remoteEnv` values in `devcontainer.json` if your project uses different paths. The configuration also assumes the workspace is mounted at `/workspace`; if you change `workspaceFolder`, update the `/workspace` paths in `containerEnv`, `remoteEnv`, and the `.bashrc` hook in `post-create.sh`.

> [!WARNING]
> Kubeconfig files usually contain credentials. Do not commit `.kube/config` unless it is safe to share.

### Design notes

A few choices are intentional and worth knowing before changing the setup:

- The non-root user uses `/bin/bash` because some Dev Container Features run `su <user> -c` snippets that rely on bash builtins.
- `libatomic1` is required by the official Node.js arm64 binaries, and `ripgrep` avoids OpenCode's arm64 fallback path.
- Mount targets are created and chowned in the image so fresh named volumes are writable by `developer`; `post-create.sh` repairs existing volumes.
- `post-create.sh` removes VS Code's `credsStore` from `~/.docker/config.json` so Docker registry auth does not fail outside a live VS Code session.
- Terminal setup falls back to `xterm-256color` when the terminal's terminfo is missing, disables flow control (`stty -ixon`), and enables bracketed paste.
- kubectl and Helm are installed directly from official release artifacts instead of the `kubectl-helm-minikube` feature. The feature was removed because this setup does not need minikube, and direct installs allow exact pins and digest verification; the feature's Copilot customization is intentionally dropped.
- The Dockerfile hardcodes the official per-architecture SHA256 digests next to the source URLs and verifies each download with `sha256sum --strict`. The repository, not a same-origin checksum, is the trust anchor.
- Helm defaults to `v4.3.1`. To use Helm 3, change `HELM_VERSION` to `v3.22.1` and update the matching per-architecture digest ARGs; Helm 3 security support ends on 2027-02-10.
- Version support is policy-specific: kubectl `v1.37.2` supports Kubernetes 1.36–1.38, while Helm 4.3.x supports Kubernetes 1.34–1.37.
- Minikube is no longer included. `kind` remains the local-cluster option; re-add the feature or install minikube manually if a project needs it.
- Existing containers retain minikube and the other old feature binaries until they are recreated. `smoke-real` will fail the new minikube-absence assertions on those containers.
- The feature's `gnupg2`/`dirmngr` installs and its conditional `jq` install are intentionally gone. Add them explicitly if a project needs GPG verification or jq.
- `KUBECONFIG` points only at the container-local `/home/developer/.kube/config`. Kubernetes client-go locks every file listed in `KUBECONFIG`; on macOS VirtioFS bind mounts a lock file can be created with mode `000`, which breaks `kind`. The `kubeconfig` volume keeps this directory on the Docker volume filesystem and preserves contexts across rebuilds. `post-create.sh` creates the file, sets it to `0600`, and removes stale lock files. Do not add `/workspace/.kube/config` to the default `KUBECONFIG`; merge a project config manually instead.
- The `developer` username is part of the test contract. If you change it, update the Dockerfile default, `remoteUser`, mounts, `remoteEnv`, and smoke tests together.

## Testing

The default smoke suite is safe to run locally. It copies the repository to `$HOME/.dc-smoke` by default, prefixes the repository's named volumes with `dcsmoke-<run-id>-`, and never touches the real repository's container or volumes. The `*-real` modes are the exception: they target the container you pass in `CID`.

### Quick checks

These do not build or start a container:

```bash
test/devcontainer-smoke.sh guard
test/devcontainer-smoke.sh static
```

### Full suite

```bash
test/devcontainer-smoke.sh all
test/devcontainer-smoke.sh cleanup
```

`all` runs the guard self-test, static checks, image build, pre- and post-create smoke tests, PTY paste tests, idempotency, container recreation, and fresh-volume tests. It can take several minutes and requires Docker plus the Dev Containers CLI. It leaves the disposable copy and volumes in place for inspection; run `cleanup` when you are done.

The PTY test covers raw paste, bracketed paste, heredocs, `TERM` fallback, and `stty -ixon` across `xterm-ghostty`, `dumb`, and `xterm-256color`.

The tests use Python 3 on the host for JSON parsing and the PTY paste test. They target Linux, macOS, or WSL. Set `SMOKE_ROOT` to move the disposable copy, `REPO` to test another checkout, or `CID` to target an existing container.

### Test modes

| Mode | What it does |
| --- | --- |
| `guard` | Verifies destructive-operation guards reject unsafe paths and volume prefixes |
| `static` | Validates JSON, feature lock, environment, mounts, Dockerfile, and shell syntax |
| `build` | Runs `static`, then builds the image and Dev Container Features |
| `pre` | Starts the container with `--skip-post-create` and checks base tooling |
| `up` | Starts the container with post-create and runs the runtime smoke test |
| `smoke` | Runs the runtime smoke test against the last container |
| `smoke-real` | Runs the runtime smoke test against the container in `CID` |
| `paste` | Runs the PTY paste regression against the last container |
| `paste-real` | Runs the PTY paste regression against the container in `CID` |
| `idempotent` | Runs `post-create.sh` twice and checks `.bashrc` stability |
| `recreate` | Recreates the container and runs the smoke test again |
| `fresh` | Removes test volumes, recreates the container, and runs the smoke test |
| `cleanup` | Removes the test container, volumes, and disposable copy |
| `all` | Runs every mode from `guard` through `fresh` (not `cleanup`) |

### Test an existing container

If you already have a container and want to run the runtime or paste checks against it:

```bash
CID=<container-id> test/devcontainer-smoke.sh smoke-real
CID=<container-id> test/devcontainer-smoke.sh paste-real
```

## Troubleshooting

### Docker is not available inside the container

The Docker-in-Docker feature needs a working Docker daemon on the host and a privileged container. Make sure Docker is running, then restart or rebuild the container. The smoke suite waits up to two minutes for the daemon to start.

### `kind` fails with `config.lock: permission denied`

This is a macOS VirtioFS issue: Kubernetes client-go locks every file listed in `KUBECONFIG`, and VirtioFS can create the lock file with mode `000`, so the next open fails. The default `KUBECONFIG` uses only the container-local `/home/developer/.kube/config`, which lives in the `kubeconfig` volume.

If you overrode `KUBECONFIG` to include a workspace path, remove it:

```bash
export KUBECONFIG=/home/developer/.kube/config
rm -f /workspace/.kube/config.lock
```

To merge a project kubeconfig into the container-local file, copy it to a temporary path on the container filesystem before flattening, so the VirtioFS path is never in `KUBECONFIG`:

```bash
cp /workspace/.kube/config /tmp/project-kubeconfig
KUBECONFIG="$HOME/.kube/config:/tmp/project-kubeconfig" kubectl config view --flatten > "$HOME/.kube/config.merged"
mv "$HOME/.kube/config.merged" "$HOME/.kube/config"
rm -f /tmp/project-kubeconfig
```

If you need a project config for read-only commands and are not using kind, you can set `KUBECONFIG=/workspace/.kube/config` explicitly; writes may still fail on macOS VirtioFS.

### Host secret mounts are empty or are directories

Create the `.env` files on the host before the first launch (see [Optional: host secrets](#optional-host-secrets)). If Docker already created a directory at the mount path, remove it and create the file before starting the container again.

### The prompt shows boxes instead of icons

`starship.toml` uses Nerd Font glyphs. Install a [Nerd Font](https://www.nerdfonts.com/) and select it in your terminal.

### Permission errors on `.local`, `.config`, or `/worktrees`

Re-run the post-create script inside the container as the `developer` user:

```bash
bash .devcontainer/post-create.sh
```

It repairs ownership for `developer` and is safe to run repeatedly.

### `--frozen-lockfile` fails

Run a normal `devcontainer build` or `devcontainer up` to refresh `.devcontainer/devcontainer-lock.json`, review the diff, and commit it. Prefer the CLI over hand edits; the only exception is the deterministic single-entry fallback below.

If CLI regeneration also churns unrelated feature entries, restore the previous lockfile and remove only the stale entry with a small JSON script, then validate with `--frozen-lockfile`. The diff must remove exactly one key and leave every other entry unchanged. For example, when removing `kubectl-helm-minikube`:

```bash
git checkout -- .devcontainer/devcontainer-lock.json
python3 - <<'PY'
import json, pathlib
p = pathlib.Path('.devcontainer/devcontainer-lock.json')
d = json.loads(p.read_text())
d['features'].pop('ghcr.io/devcontainers/features/kubectl-helm-minikube:1', None)
p.write_text(json.dumps(d, indent=2) + '\n')
PY
devcontainer build --workspace-folder . --frozen-lockfile
```

### Changing the `developer` user

The username appears in the Dockerfile default, `remoteUser`, the mounts, `remoteEnv.PATH`, and the smoke tests. Update all of them and run `test/devcontainer-smoke.sh static`.

## Learn more

- [Development Containers specification](https://containers.dev)
- [Dev Container Features](https://containers.dev/features)
- [Dev Containers CLI](https://github.com/devcontainers/cli)
- [OpenCode](https://opencode.ai)
- [GitHub Spec Kit](https://github.com/github/spec-kit)
- [Starship](https://starship.rs)
