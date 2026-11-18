<div align="center">

<img src="assets/icon.svg" alt="devcontainer-base icon" width="96" />

# devcontainer-base

**A batteries-included Dev Container for polyglot, cloud-native, and AI-assisted development.**

[![Dev Containers](https://img.shields.io/badge/Dev_Containers-spec-2753E3?style=flat-square&logo=visualstudiocode&logoColor=white)](https://containers.dev)
[![Debian 12](https://img.shields.io/badge/Debian-12-A81D33?style=flat-square&logo=debian&logoColor=white)](https://www.debian.org)
[![OpenCode](https://img.shields.io/badge/OpenCode-2.3.0-000000?style=flat-square)](https://opencode.ai)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue?style=flat-square)](LICENSE)

[Overview](#overview) • [What's included](#whats-included) • [Quick start](#quick-start) • [Use it in your project](#use-it-in-your-project) • [Configuration](#configuration) • [Testing](#testing) • [Troubleshooting](#troubleshooting)

</div>

A reusable [Dev Container](https://containers.dev) definition that turns a fresh checkout into a ready-to-code Linux environment. It combines a slim Debian base with language runtimes, Docker and Kubernetes tooling, an AI coding agent, and a tuned shell, so every project and every teammate starts from the same setup.

> [!NOTE]
> This repository is a base configuration, not a published container image. Open it directly to work on the environment itself, or copy `.devcontainer/` into a project that needs it.

## Overview

`devcontainer-base` is made for projects that need more than a single runtime, and for workflows that mix local containers, a Kubernetes cluster, and an AI coding agent in the same workspace. It is a good fit for platform, backend, and AI projects that want a consistent environment without maintaining a bespoke Dockerfile for every repository.

- **Polyglot by default** — Node.js, Bun, Python with uv, and Go are ready to use.
- **Cloud-native tooling** — Docker-in-Docker, Compose, Buildx, kubectl, Helm, kind, and kubectx/kubens.
- **AI-assisted workflow** — OpenCode, persistent tool state, and short-lived GitHub App installation tokens for `gh` and `git`.
- **Comfortable shell** — Starship prompt, useful aliases, kubectl and Helm completion, paste-safe terminal settings, and a configurable system timezone that defaults to US/Pacific.
- **Reproducible** — pinned build-time tools and a Dev Container feature lockfile.
- **Tested** — a smoke suite covers build, runtime, multi-repo clone/worktree, shell paste, idempotency, volume lifecycle, and timezone overrides.

## What's included

| Area | Details |
| --- | --- |
| **Base** | `debian:bookworm-slim`, non-root `developer` user (UID/GID 1000 by default), passwordless sudo, `en_US.UTF-8` locale, `TZ=America/Los_Angeles` (US/Pacific, overridable with `DEVCONTAINER_TZ`), `tzdata`, bash |
| **Languages** | Node.js + npm, Bun, Python 3 + uv, Go |
| **Containers** | Docker-in-Docker, Docker Compose, Buildx |
| **Kubernetes** | kubectl, Helm, kind, kubectx, kubens |
| **CLI tools** | git, GitHub CLI (`gh`), fzf, ripgrep (`rg`), Glow (`glow`) with `less` pager, curl, OpenSSH client, unzip, zip, yq |
| **AI & workflow** | OpenCode 2.3.0, Neovim 0.12.6, Starship 1.27.0 |
| **Rendering** | Firefox ESR (headless) for the official Excalidraw CLI and PNG diagram rendering |
| **Shell** | aliases from `aliases.sh`, a `k` wrapper (`k ns`, `k ctx`, otherwise kubectl), kubectl and Helm completion, bracketed paste, TERM fallback, Starship prompt |
| **Persistence** | named volumes for OpenCode, OpenTUI, uv, Neovim, and Kubernetes config; repo clones live in the workspace |

> [!NOTE]
> The upstream tools installed in the Dockerfile (`yq`, Glow, kubectl, Helm, OpenCode, Neovim, and Starship) are pinned with build args. Language runtime versions are provided by Dev Container Features; pin them with feature options if your project needs exact versions. The resolved feature versions are stored in `devcontainer-lock.json`.

### Pinned build-time tools

| Tool | Version |
| --- | --- |
| [yq](https://github.com/mikefarah/yq) | `v4.54.3` |
| [Glow](https://github.com/charmbracelet/glow) | `v3.0.0` |
| [kubectl](https://kubernetes.io/docs/reference/kubectl/) | `v1.37.2` |
| [Helm](https://helm.sh) | `v4.3.1` |
| [OpenCode](https://opencode.ai) | `2.3.0` |
| [Neovim](https://neovim.io) | `v0.12.6` |
| [Starship](https://starship.rs) | `v1.27.0` |

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

Copy `.devcontainer/` and `.opencode/` into the project you want to develop:

```bash
git clone --depth 1 https://github.com/dzmoore/devcontainer-base.git /tmp/devcontainer-base
mkdir -p .devcontainer .opencode
cp -R /tmp/devcontainer-base/.devcontainer/. .devcontainer/
cp -R /tmp/devcontainer-base/.opencode/. .opencode/
rm -rf /tmp/devcontainer-base
```

If the project already has a `.devcontainer/` or `.opencode/`, merge the files instead of overwriting them. Then update the `"name"` in `devcontainer.json` if you like, and reopen the project in the container. The rest of the configuration is self-contained.

> [!TIP]
> If you use [`degit`](https://github.com/Rich-Harris/degit), you can copy just the configuration with `npx degit dzmoore/devcontainer-base/.devcontainer .devcontainer`.

### Optional: host secrets

Two read-only bind mounts make host-side secrets available inside the container:

- `~/.devcontainer/github/` provides GitHub credentials. `.env` can hold `GITHUB_TOKEN` for `gh` and the `post-create.sh` Helm `ghcr.io` login, plus the GitHub App variables. `app.pem` holds the App private key.
- `~/.devcontainer/brave/.env` provides `BRAVE_API_KEY` to tools that read it, such as Brave Search integrations.

Create the files on the host before the first launch:

```bash
mkdir -p ~/.devcontainer/github ~/.devcontainer/brave
chmod 700 ~/.devcontainer/github
printf 'GITHUB_TOKEN=%s\n' "$GITHUB_TOKEN" > ~/.devcontainer/github/.env
printf 'BRAVE_API_KEY=%s\n' "$BRAVE_API_KEY" > ~/.devcontainer/brave/.env
chmod 600 ~/.devcontainer/github/.env ~/.devcontainer/brave/.env
```

To use the GitHub App flow instead of, or in addition to, the PAT, put the App variables in the same `.env` and place the private key at `~/.devcontainer/github/app.pem`; see [GitHub App tokens](#github-app-tokens). The existing `/home/developer/.dc/github/.env` path does not change because the whole directory is mounted read-only.

The files are mounted read-only and sourced by interactive bash shells. If you do not need them, remove the corresponding entries from `mounts` in `devcontainer.json`.

> [!IMPORTANT]
> Create the GitHub directory and files before the first launch. The GitHub source is now a directory mount; Docker may create a missing directory for it. The Brave source is still a single file, so if Docker creates a directory at `~/.devcontainer/brave/.env`, remove it and create the file before starting the container again.

### Working with multiple repositories

`host-init.sh` creates `repos/` in the project root and adds `repos/` to the repository's real git exclude (`git rev-parse --git-path info/exclude`), so clones never show up as untracked files. The workspace bind mount exposes that directory as `/workspace/repos`, and `/worktrees` is a compatibility symlink to the same path. Clones are ordinary workspace files, so they persist without a named volume.

Use the `repo` helper, which `post-create.sh` symlinks into `~/.local/bin`:

```bash
repo clone dzmoore/provider-confluent --upstream crossplane-contrib/provider-confluent
repo switch main
repo switch --create feature/my-change
repo pr 123
repo worktree experiment feature/experiment
repo list
```

- `repo clone <owner>/<repo>` clones to `/workspace/repos/<owner>/<repo>`; `--upstream` adds an `upstream` remote and fetches it.
- `repo clone` also accepts a `file://` URL or absolute path, which is useful for local bare remotes.
- `repo fork <upstream-owner>/<repo> <fork-owner>` clones the fork and adds the upstream.
- `repo switch <branch>` uses `git switch`; pass `--create` to create the branch.
- `repo pr <number>` runs `gh pr checkout`.
- `repo worktree <name> <branch>` creates `/workspace/repos/.worktrees/<owner>/<repo>/<name>`.
- `repo list` prints each clone, its branch, and whether it is dirty.

`repo` uses the GitHub App helper when the `GITHUB_APP_*` variables are present in the environment or `~/.dc/github/.env`: it runs `gh-app-token check`, then uses `gh-app` for `gh` commands and the `gh-app-token git-credential` helper for network `clone`/`fetch`. If the App is configured but the check fails, the command prints the error and stops instead of silently downgrading. Without App variables it sources `~/.dc/github/.env` when `GITHUB_TOKEN` is unset, exports `GH_TOKEN`, and uses plain `gh`/`git`. Tokens are never written into a remote URL.

#### Migrating from the old `worktrees` volume

Earlier versions mounted a named `worktrees` volume at `/worktrees`. Move any clones or worktrees you want to keep into `/workspace/repos`, remove the `source=worktrees` mount from `devcontainer.json`, and recreate the container. After moving a worktree, run `git worktree repair` in the main clone so Git records the new path:

```bash
git worktree repair /workspace/repos/<owner>/<repo>/<worktree-name>
```

If `/worktrees` is still an old volume mountpoint or a non-empty directory, `post-create.sh` prints a migration warning and leaves it untouched. A fresh container creates `/worktrees` as a symlink to `/workspace/repos`.

## Configuration

### Files

| Path | Purpose |
| --- | --- |
| `.devcontainer/Dockerfile` | Debian base, non-root user, locale, timezone default, and pinned CLI tools |
| `.devcontainer/devcontainer.json` | Features, mounts, environment, and lifecycle hooks |
| `.devcontainer/devcontainer-lock.json` | Resolved Dev Container Feature versions |
| `.devcontainer/post-create.sh` | Idempotent setup: timezone reconcile, host secret validation, env loading, ownership repair, shell hooks, helper symlinks, Helm login |
| `.devcontainer/host-init.sh` | Host-side init: create the overlay directories and the multi-repo workspace, and ignore `repos/` |
| `.devcontainer/examples/opencode/` | Example host MCP configuration and `research` agent override |
| `.devcontainer/bin/gh-app-token` | GitHub App installation token CLI: token, JSON, check, exec, and Git credential modes |
| `.devcontainer/bin/gh-app` | Wrapper that runs `gh` with a freshly minted installation token |
| `.devcontainer/bin/repo` | Multi-repo helper: clone, fork, list, switch, pr, and worktree |
| `.devcontainer/aliases.sh` | Interactive shell aliases |
| `.devcontainer/starship.toml` | Starship prompt configuration |
| `opencode.jsonc` | OpenCode project config; minimal and defines no MCP servers |
| `.opencode/agents/research.md` | Research subagent definition and write/network permissions |
| `.opencode/skills/run-research/` | Research orchestration skill and report template |
| `.opencode/agents/copy-writer.md` | Copy writer subagent definition, skill routing, and prose and diagram permissions |
| `.opencode/skills/technical-writer/` | 10 vendored technical-writer skills, MIT license, and upstream pin |
| `.opencode/skills/elements-of-style/` | Vendored Elements of Style reference and local wrapper |
| `.opencode/skills/diagramming-processes/` | Local Excalidraw-only diagramming skill, references, and templates |
| `.opencode/skills/writing-commits-and-pull-requests/` | Local skill for commit messages, pull request text, and review comments |
| `NOTICE` | Third-party writing material attribution |
| `scripts/render-excalidraw.sh` | Render `.excalidraw` sources to PNG beside them |
| `scripts/update-writing-skills.sh` | Refresh or verify the vendored writing skills |
| `research/` | Local research artifacts (gitignored) |
| `repos/` | Local multi-repo clones (gitignored, created by host-init) |
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
> The runtime smoke test derives the expected yq, kubectl, and Helm versions from their `ARG`s in `.devcontainer/Dockerfile`, so the assertions stay in step with the pins automatically. It derives the expected timezone from the effective `TZ`. The `pre` mode runs before `post-create.sh` reconciles a `containerEnv` override; its `env: TZ` check compares against a literal `containerEnv.TZ` when one is set, and otherwise checks that `TZ` is non-empty for the `DEVCONTAINER_TZ` template. Its `/etc/localtime`, `/etc/timezone`, and offset checks compare against the image baseline from `ARG TZ`.

### Change the timezone

The image sets the system timezone to `America/Los_Angeles` (US/Pacific) from `ARG TZ` in `.devcontainer/Dockerfile`, and `ENV TZ` exposes it to processes. `US/Pacific` is a compatibility alias for the canonical `America/Los_Angeles` name.

`containerEnv.TZ` is set to `${localEnv:DEVCONTAINER_TZ:America/Los_Angeles}` in `devcontainer.json`: when `DEVCONTAINER_TZ` is unset, US/Pacific applies; when it is set, that zone wins. To change the zone without editing a tracked file, export it on the host and recreate:

```bash
DEVCONTAINER_TZ=Asia/Tokyo devcontainer up --workspace-folder . --remove-existing-container
```

Unset `DEVCONTAINER_TZ` to return to US/Pacific. Do not set it to an empty string; unset is the default. If you prefer a literal in the project file, replace the `TZ` template in the existing `containerEnv` object with a zone name, keeping `LANG` and `LC_ALL`:

```jsonc
"containerEnv": {
  "LANG": "en_US.UTF-8",
  "LC_ALL": "en_US.UTF-8",
  "TZ": "Asia/Tokyo",
  "STARSHIP_CONFIG": "/workspace/.devcontainer/starship.toml",
  "EDITOR": "nvim",
  "VISUAL": "nvim"
}
```

Use a real IANA zone file under `/usr/share/zoneinfo`. Non-zone entries such as `localtime`, `leapseconds`, and `posixrules` are rejected, as are directories, empty values, paths with `..`, and multiline values. The validator resolves the target inside `/usr/share/zoneinfo` and requires the `TZif` magic header, so a symlink that escapes the zoneinfo tree also fails. Use `DEVCONTAINER_TZ` or a literal IANA name; do not use the generic host `TZ`. Then recreate the container so `containerEnv` is applied:

```bash
devcontainer up --workspace-folder . --remove-existing-container
```

In VS Code, `${localEnv:...}` is resolved from the environment of the process that starts the dev container: launch VS Code from a shell with `DEVCONTAINER_TZ` exported, or use a literal in `devcontainer.json`. A GUI-launched VS Code may not see a shell-only export. Run **Dev Containers: Rebuild Container**; it re-creates the container, and the image build is normally a cache hit. A `containerEnv.TZ` change does not require an image change. For a CLI-only recreate without an image change, use the `devcontainer up --remove-existing-container` command above.

`post-create.sh` reconciles `/etc/localtime` and `/etc/timezone` from the effective `TZ`, so programs and clean-environment consumers agree with `date`. Invalid values — an unknown zone, a directory such as `America` or `Etc`, an empty value, or a path with `..` — fail with `Invalid TZ` instead of silently falling back to UTC.

> [!NOTE]
> To change the image default itself, edit `ARG TZ` in the Dockerfile and rebuild. `build.args.TZ` is not supported. The `DEVCONTAINER_TZ` template default and `ARG TZ` are part of the static test contract, so update the matching assertion in `test/devcontainer-smoke.sh` in the same change.

> [!IMPORTANT]
> Containers created before the timezone change have no `ENV TZ` and still have `/etc/timezone` set to `Etc/UTC`. Running `post-create.sh` manually keeps UTC because the fallback reads `/etc/timezone`; recreate the container to pick up the new image.

### Project-local configuration

The config keeps the writable Kubernetes config inside the container and leaves OpenCode's project settings in the workspace:

- `KUBECONFIG=/home/developer/.kube/config` — the container-local file lives in the `kubeconfig` volume and is where kind and kubectl write new contexts. It is intentionally the only default path: client-go locks every file in `KUBECONFIG`, and a workspace path on macOS VirtioFS can break `kind`. To use a project kubeconfig at `.kube/config`, merge or copy it manually; see [kind fails with `config.lock: permission denied`](#kind-fails-with-configlock-permission-denied).
- `opencode.jsonc` in the workspace root — OpenCode discovers project config automatically. This repository keeps it minimal: it defines no MCP servers. The Superpowers plugin is loaded by `.opencode/opencode.global.json`; add project-specific OpenCode settings to the same file.
- `STARSHIP_CONFIG=/workspace/.devcontainer/starship.toml` — the prompt config shipped with this base.

Change the `containerEnv` and `remoteEnv` values in `devcontainer.json` if your project uses different paths. The configuration also assumes the workspace is mounted at `/workspace`; if you change `workspaceFolder`, update the `/workspace` paths in `containerEnv`, `remoteEnv`, and the `.bashrc` hook in `post-create.sh`.

> [!WARNING]
> Kubeconfig files usually contain credentials. Do not commit `.kube/config` unless it is safe to share.

### Host MCP and agent overrides

All MCP servers come from a host-owned overlay mounted read-only at
`/etc/opencode`. The project `opencode.jsonc` defines no MCP servers. The
`initializeCommand` hook runs `bash .devcontainer/host-init.sh` before the
container starts. The script creates `~/.devcontainer/opencode/` with `secrets/`,
`agents/`, and `skills/` subdirectories, sets mode `700` on the overlay and
`secrets/`, and never copies the examples or overwrites a file.

Create the overlay and the secret files on the host:

```bash
mkdir -p ~/.devcontainer/opencode/secrets
chmod 700 ~/.devcontainer/opencode ~/.devcontainer/opencode/secrets
printf '%s\n' "$BRAVE_API_KEY" > ~/.devcontainer/opencode/secrets/brave_api_key
chmod 600 ~/.devcontainer/opencode/secrets/brave_api_key
```

The canonical example is `.devcontainer/examples/opencode/opencode.json`. It
defines `parallel-search` and `brave-search-mcp-server`; the Brave server reads
`BRAVE_API_KEY` from `{file:/etc/opencode/secrets/brave_api_key}`. Copy it to
`~/.devcontainer/opencode/opencode.json` and edit it for your host; do not add
MCP servers to a repository. The example agent override is
`.devcontainer/examples/opencode/agents/research.md`; copy it to
`~/.devcontainer/opencode/agents/research.md` to replace the research body while
inheriting the model and permissions.

`post-create.sh` validates every `{file:/etc/opencode/...}` reference in the
overlay before OpenCode starts. It fails with the exact path when a referenced
file is missing, unreadable, or empty. Do not print or log secret values.

> [!WARNING]
> The overlay is mounted read-only, which protects the host copy from accidental
> modification, not from disclosure. Any process running as `developer` in the
> container can read the overlay, and the container is privileged for
> Docker-in-Docker. Host configuration is trusted and can weaken project policy,
> so review it like code. A repository without the host overlay has no MCP
> servers, including no research MCP servers.

Docs-only agents such as `copy-writer` must deny every host search or
write-capable MCP server. The base agent denies the two known servers,
`parallel-search_*` and `brave-search-mcp-server_*`. If the host adds another
such server, append a deny rule to the host copy at
`~/.devcontainer/opencode/agents/copy-writer.md`; permission rules append to the
base rules.

### GitHub App tokens

The `gh-app-token` helper mints short-lived GitHub App installation tokens on demand, so `gh`, `git`, and agents do not need a long-lived PAT in the container. It signs an RS256 JWT with the App private key and exchanges it at `POST /app/installations/<id>/access_tokens`. The App client secret is not used for this flow and should not be placed in the container.

The App must be installed on the target user or organization, with the repository access and permissions your commands need; an installation token cannot exceed them. Copy the installation ID from the App installation settings URL or from `GET /app/installations`.

Host files:

```text
~/.devcontainer/github/
  .env       # App ids plus optional GITHUB_TOKEN
  app.pem    # GitHub App private key
```

Example `.env`:

```dotenv
GITHUB_APP_CLIENT_ID=Iv1.example
GITHUB_APP_INSTALLATION_ID=12345678
# Optional (defaults shown):
# GITHUB_APP_PRIVATE_KEY_FILE=/home/developer/.dc/github/app.pem
# GITHUB_APP_ENV_FILE=/home/developer/.dc/github/.env
# GITHUB_API_URL=https://api.github.com
# GITHUB_SERVER_URL=https://github.com
# GITHUB_API_VERSION=2026-03-10
# Existing PAT fallback for Helm and other tools:
# GITHUB_TOKEN=ghp_example
```

`GITHUB_APP_CLIENT_ID` is preferred; `GITHUB_APP_ID` works as a fallback. The key path and env-file path are container paths. Both `GITHUB_API_URL` and `GITHUB_SERVER_URL` must use HTTPS, except for loopback test URLs. Set `GITHUB_API_VERSION` to match an older GitHub Enterprise Server instance, or leave it empty to omit the header.

`post-create.sh` symlinks both helpers into `~/.local/bin`, which is on the agent PATH:

```bash
gh-app-token                       # print a token
gh-app-token check                 # mint and summarize without printing the token
gh-app-token json                  # full API response, including expires_at
gh-app-token token --repo owner/repo --permission contents=write
gh-app-token exec -- gh pr list    # run one command with GH_TOKEN/GITHUB_TOKEN
gh-app pr list                     # wrapper around gh
```

`exec` sets `GH_HOST` and the matching `gh` variables: `GH_TOKEN`/`GITHUB_TOKEN` for `github.com`, `github.localhost`, and `*.ghe.com`; `GH_ENTERPRISE_TOKEN`/`GITHUB_ENTERPRISE_TOKEN` for other hosts. For a true GitHub Enterprise Server host, `gh` may infer a host from a repository remote, so run it in trusted repositories or verify the remote.

To let Git authenticate without exporting a token, install the credential helper for your host:

```bash
git config --global --replace-all credential.https://github.com.helper \
  '!/home/developer/.local/bin/gh-app-token git-credential'
```

For GitHub Enterprise Server, replace `github.com` with the server host and set `GITHUB_SERVER_URL`. The helper only answers HTTPS requests for the configured host and port.

Installation tokens expire after about one hour. The script mints on demand and does not cache them. The Helm `ghcr.io` login still uses `GITHUB_TOKEN` (or a manual login), because a one-hour installation token is not suitable for a persistent Helm registry login. A user-level Git credential store can still store or cache a token after the helper returns it (`store`, `osxkeychain`, and `manager` persist to disk; `cache` keeps it in memory); remove or scope such helpers for GitHub if that matters.

`token` and `json` output is sensitive. `gh-app` keeps the token in the child environment, and Git consumes the credential helper output directly.

The read-only mount protects the host copy from modification, not from container processes: any process running as `developer` in the container can read `app.pem` and mint tokens. Keep the App's permissions minimal and treat container access as App access.

Editing `.env` in a live interactive shell leaves the old exported values in that shell because process environment wins. Run `reload` or open a new shell after changing it.

### Research subagent

The project config also defines a `research` subagent and a `run-research` skill for evidence-backed web research. Parallel Search and Brave Search are configured in `~/.devcontainer/opencode/opencode.json` and mounted read-only at `/etc/opencode`; the project `opencode.jsonc` defines no MCP servers. The subagent uses those host servers as its primary and only search path; OpenCode's built-in `websearch` is disabled for the `research` agent.

Invoke the skill with a research question:

```text
@run-research find the best socket wrench that is recommended by community users and is affordable, and is available currently on amazon
```

The skill frames the question, launches several `research` subagents in parallel, runs an independent verification pass over the decision-driving claims, and writes a cited report. All artifacts go in one run folder:

```text
research/<YYYY-MM-DD>-<slug>/
├── brief.md
├── notes-community.md
├── notes-expert.md
├── notes-price-availability.md
├── notes-reliability.md
├── notes-alternatives.md   # optional fifth angle
├── verification.md
└── report.md
```

`research/` is gitignored; do not commit reports or evidence notes. The `research` subagent can write only under `research/**` and cannot use shell or Code Mode, launch subagents, or ask the user.

`BRAVE_API_KEY` must be set before OpenCode starts. If it is missing or either host MCP server fails, the research agents continue with the other provider and record the degraded mode. A repository without the host overlay has no research MCP servers at all. If both MCPs are unavailable, the run marks the affected claims `unverified` rather than falling back to built-in search. Amazon detail pages and Reddit may block fetching; the report marks those claims `unverified` rather than inventing them.

### Copy writer subagent

The project config defines a `copy-writer` subagent for finished prose and
Excalidraw diagrams: documentation, READMEs, design docs, ADRs, runbooks,
changelogs, postmortems, issue descriptions, API references, commit messages,
pull request descriptions and comments, release notes, error messages, and
other text a human will read, plus process, lifecycle, and interaction
diagrams. It loads the vendored writing skills by default and applies the house
rules: conclusion first, every claim traceable, one fact in one home, plain
English, and no em dashes or AI tells.

Ask the primary agent to use it:

```text
Use the copy-writer subagent to rewrite the README introduction for a platform team.
```

```text
Use the copy-writer subagent to write a commit message for the staged changes.
```

The agent writes prose and `.excalidraw` source files directly and returns
commit messages, pull request descriptions, and pull request comments as
ready-to-paste text. It does not commit, post, push, or open pull requests. It
can run a narrow set of read-only `git` and `gh` commands, plus
`scripts/render-excalidraw.sh` to render a diagram PNG. It cannot use the web,
launch subagents, or edit code and configuration.

#### Vendored writing skills

| Skill | Source | Purpose |
| --- | --- | --- |
| `technical-writing` | technical-writer | Core house style, truth rules, and banned constructions |
| `writing-design-docs`, `recording-decisions`, `writing-changelogs`, `writing-runbooks`, `writing-issues`, `writing-postmortems` | technical-writer | Document-type formats |
| `documenting-contracts`, `documenting-legacy-codebases` | technical-writer | API and legacy documentation |
| `reviewing-technical-prose` | technical-writer | Final review pass |
| `writing-clearly-and-concisely` | the-elements-of-style | Strunk's 1918 rules and full reference |
| `diagramming-processes` | This repository, adapted from technical-writer and awesome-copilot | Excalidraw process and lifecycle diagrams, source plus PNG |
| `writing-commits-and-pull-requests` | This repository | Commit, pull request, and review-comment formats |

The technical-writer skills are vendored from
[riekelt/technical-writer](https://github.com/riekelt/technical-writer) at
commit `85e5372` (v1.8.4, MIT). The Elements of Style reference is vendored
from [obra/the-elements-of-style](https://github.com/obra/the-elements-of-style)
at commit `05fc4f0` (1918 text, public domain). The `diagramming-processes`
skill is local and adapted from technical-writer and
[github/awesome-copilot](https://github.com/github/awesome-copilot)'s
`excalidraw-diagram-generator` skill (MIT). `writing-commits-and-pull-requests`
is local to this repository.

At the pinned commit, the Elements of Style repository has no license file.
The 1918 text is public domain; the wrapper at
`.opencode/skills/elements-of-style/` is a local adaptation that points at the
verbatim text. See the `UPSTREAM.md` files for the exact pins and attribution.

#### Diagrams

For process, lifecycle, and interaction diagrams, the skill writes an
`.excalidraw` source and renders a `.png` beside it with
`scripts/render-excalidraw.sh`. The `.excalidraw` file is the editable source;
the PNG is for Markdown. Commit both.

```bash
scripts/render-excalidraw.sh docs/diagrams/refund-process.excalidraw
```

The renderer uses the official `@excalidraw/cli` 0.3.0 through the headless
Firefox ESR installed in the devcontainer. It downloads the pinned CLI on first
use and uses the npm cache after that. Firefox ESR adds about 272 MB plus its
GTK and Mesa dependencies to the image; the CLI does not download a browser.
The `diagramming-processes` skill is not refreshed by
`scripts/update-writing-skills.sh`; it is repository-owned.

To refresh the vendored trees, run `scripts/update-writing-skills.sh`; use
`--check` to verify that the working tree matches the pinned commits. To
change a pin, edit the constants at the top of the script and update the
matching `UPSTREAM.md` and `NOTICE` in the same commit. Both commands need
network access and are not part of the smoke suite.

### Design notes

A few choices are intentional and worth knowing before changing the setup:

- The non-root user uses `/bin/bash` because some Dev Container Features run `su <user> -c` snippets that rely on bash builtins.
- Firefox ESR is installed only for headless Excalidraw rendering. It is not a user-facing browser; it adds about 272 MB plus GTK and Mesa dependencies, and the official CLI drives it through Playwright's Firefox channel.
- `libatomic1` is required by the official Node.js arm64 binaries, and `ripgrep` avoids OpenCode's arm64 fallback path.
- `less` is installed from Debian because Glow's `--pager` mode defaults to `less -r`, and `debian:bookworm-slim` does not include a pager.
- Mount targets are created and chowned in the image so fresh named volumes are writable by `developer`; `post-create.sh` repairs existing volumes.
- `post-create.sh` removes VS Code's `credsStore` from `~/.docker/config.json` so Docker registry auth does not fail outside a live VS Code session.
- The GitHub credential source is a read-only directory mount so `app.pem` can sit next to `.env`; the in-container `.env` path is unchanged. `gh-app-token` is dependency-free Python 3 plus the `openssl` CLI, and `post-create.sh` symlinks it and `gh-app` into `~/.local/bin`.
- The App client secret is not needed for installation tokens and is deliberately not mounted. The helper mints tokens on demand without caching; `check`, `exec`, and `git-credential` avoid printing tokens, while `token` and `json` are explicitly sensitive. Read-only protects the host copy, not confidentiality: any `developer` process can read `app.pem` and mint tokens, so keep App permissions minimal.
- The Helm `ghcr.io` login remains PAT-backed because installation tokens expire after about an hour.
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
- The timezone precedence is the image baseline (`ARG TZ` → `ENV TZ`), then `containerEnv.TZ` (the `${localEnv:DEVCONTAINER_TZ:America/Los_Angeles}` template; an unset host variable means US/Pacific), then `post-create.sh`, which reconciles `/etc/localtime` and `/etc/timezone`. `TZ` is deliberately not set in `remoteEnv`, which affects only the Dev Containers tool and its terminal processes, not `docker exec`, daemons, or clean login shells, and it is not exported from `.bashrc`, which would make interactive and non-interactive environments disagree. Programs such as `sudo -i`, `su -`, cron, and dockerd may drop `TZ`, so they rely on `/etc/localtime`; post-create keeps that file and `/etc/timezone` in step with the effective zone.

## Testing

The default smoke suite is safe to run locally. It copies the repository to `$HOME/.dc-smoke` by default, prefixes the repository's named volumes with `dcsmoke-<run-id>-`, and never touches the real repository's container or volumes. The `*-real` modes are the exception: they target the container you pass in `CID`.

### Quick checks

These do not build or start a container:

```bash
test/devcontainer-smoke.sh guard
test/devcontainer-smoke.sh static
test/devcontainer-smoke.sh app-token
```

### Full suite

```bash
test/devcontainer-smoke.sh all
test/devcontainer-smoke.sh cleanup
```

`all` runs the guard self-test, static checks, GitHub App token tests, image build, pre- and post-create smoke tests, PTY paste tests, idempotency, container recreation, fresh-volume tests, and the timezone override and invalid-zone checks. It can take several minutes and requires Docker plus the Dev Containers CLI. It leaves the disposable copy and volumes in place for inspection; run `cleanup` when you are done.

The PTY test covers raw paste, bracketed paste, heredocs, `TERM` fallback, and `stty -ixon` across `xterm-ghostty`, `dumb`, and `xterm-256color`.

The runtime smoke suite also clones a hermetic local bare remote with `repo clone`, creates a worktree with `repo worktree`, and asserts both paths. It uses a temporary `REPO_ROOT` and a `file://` URL, so it needs no network access or GitHub credentials.

Timezone coverage is layered: `static` checks the Dockerfile default, `tzdata`, and the post-create block; `pre` proves the image is correct with `--skip-post-create`; `up`, `smoke`, and `idempotent` prove the reconciled runtime state. The offset assertions use fixed UTC instants in July and January, so they exercise daylight saving rules without depending on the current date.

The tests use Python 3 on the host for JSON parsing and the PTY paste test, and Python 3 plus OpenSSL for the GitHub App token tests. They target Linux, macOS, or WSL. Set `SMOKE_ROOT` to move the disposable copy, `REPO` to test another checkout, or `CID` to target an existing container.

### Test modes

| Mode | What it does |
| --- | --- |
| `guard` | Verifies destructive-operation guards reject unsafe paths and volume prefixes |
| `static` | Validates JSON, feature lock, environment, mounts, Dockerfile, and shell syntax |
| `app-token` | Runs the host-side GitHub App token tests; no container or real GitHub API needed |
| `build` | Runs `static`, then builds the image and Dev Container Features |
| `pre` | Starts the container with `--skip-post-create` and checks base tooling |
| `up` | Starts the container with post-create and runs the runtime smoke test |
| `smoke` | Runs the runtime smoke test against the last container |
| `smoke-real` | Runs the runtime smoke test against the container in `CID` |
| `paste` | Runs the PTY paste regression against the last container |
| `paste-real` | Runs the PTY paste regression against the container in `CID` |
| `idempotent` | Runs `post-create.sh` twice and checks `.bashrc` and timezone-state stability |
| `recreate` | Recreates the container and runs the smoke test again |
| `fresh` | Removes test volumes, recreates the container, and runs the smoke test |
| `tz` | Applies a `containerEnv.TZ=Asia/Tokyo` override with and without post-create, then rejects invalid zones; requires a prior `build` (or `all`), as the other container modes do |
| `cleanup` | Removes the test container, volumes, and disposable copy |
| `all` | Runs every lifecycle mode from `guard` through `tz` (excludes `smoke-real`, `paste-real`, and `cleanup`) |

### Test an existing container

If you already have a container and want to run the runtime or paste checks against it:

```bash
CID=<container-id> test/devcontainer-smoke.sh smoke-real
CID=<container-id> test/devcontainer-smoke.sh paste-real
```

> [!NOTE]
> `smoke-real` requires `TZ` in the container environment. Containers created before the timezone change have no `ENV TZ` and fail the new `env: TZ` check until they are recreated.
>
> New-format containers also need `/workspace/repos` and `/worktrees` as a symlink to it; recreate older containers so `post-create.sh` can apply both. The local `repo clone`/`repo worktree` exercise uses the hermetic bare remote created in the disposable copy, so it runs only in the `prepare_copy` modes and is skipped for `smoke-real`.

## Troubleshooting

### Docker is not available inside the container

The Docker-in-Docker feature needs a working Docker daemon on the host and a privileged container. Make sure Docker is running, then restart or rebuild the container. The smoke suite waits up to two minutes for the daemon to start.

### The time is UTC or the wrong timezone

Check the effective environment and system files inside the container:

```bash
date
echo "$TZ"
readlink -f /etc/localtime
cat /etc/timezone
```

If `TZ` is unset or the files report `Etc/UTC`, the container is older than the timezone change or was created without the image `ENV TZ`. Containers created before the change have no `ENV TZ` and still report `Etc/UTC`; running `post-create.sh` manually keeps UTC because the fallback reads `/etc/timezone`. Recreate the container instead:

```bash
devcontainer up --workspace-folder . --remove-existing-container
```

If you set `DEVCONTAINER_TZ` on the host, recreate the container so the value is applied; `echo "${DEVCONTAINER_TZ:-<unset>}"` shows the host value, and unset means US/Pacific. If you edit `containerEnv.TZ` in `devcontainer.json`, recreate the container after editing it; a restart does not apply `containerEnv`. If `post-create.sh` fails with `Invalid TZ`, fix the value to a real IANA zone file under `/usr/share/zoneinfo` and recreate. The validator resolves the target inside `/usr/share/zoneinfo` and requires the `TZif` magic header; it rejects unknown zones, non-zone entries such as `localtime`, `leapseconds`, and `posixrules`, directories, empty values, paths with `..`, multiline values, and paths that escape the zoneinfo tree.

This is a timezone problem, not a clock problem. The container uses the host/VM clock and cannot set it; `date -u` reflects that clock. If `date -u` itself is wrong, fix the Docker Desktop, WSL2, or colima VM clock instead.

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

Create the GitHub directory and `.env` files on the host before the first launch (see [Optional: host secrets](#optional-host-secrets)). The GitHub source is a directory mount; if it is missing, add `.env` and `app.pem` and restart the container. The Brave source is a single file; if Docker created a directory at `~/.devcontainer/brave/.env`, remove it and create the file before starting the container again.

### `gh-app-token` reports missing configuration

Create `~/.devcontainer/github/.env` with `GITHUB_APP_CLIENT_ID` (or `GITHUB_APP_ID`) and `GITHUB_APP_INSTALLATION_ID`, and put the private key at `~/.devcontainer/github/app.pem` (or set `GITHUB_APP_PRIVATE_KEY_FILE` to its in-container path). Recreate the container after changing the mount or host files. `gh-app-token check` verifies the setup end to end without printing the token.

### GitHub App token request fails

- HTTP 401: usually a wrong client ID or private key, clock skew, or an expired JWT. Check the App settings and the host clock, then retry.
- HTTP 404: the installation ID is wrong, or the App is not installed on that account. Copy the installation ID again from the App installation settings.
- HTTP 403: the App installation does not have the requested repository access or permission. Adjust the App installation or the `--repo`/`--permission` scope.
- `GITHUB_API_URL`/`GITHUB_SERVER_URL` errors: use HTTPS (except loopback test URLs) and a valid host and port. Set `GITHUB_API_VERSION` to match an older GitHub Enterprise Server instance, or leave it empty to omit the header.
- A malformed `.env` line reports the path and line number without echoing the value. Fix the line to `KEY=VALUE`.

### `git push` does not use the App token

Install the credential helper for the host you use. The helper only answers HTTPS requests for the configured host and port, and it returns no credentials for HTTP, a different host, or a different port. Check that the App has `Contents` access to the repository. If a user-level `credential.helper` such as `store`, `osxkeychain`, or `manager` is also configured, Git may persist the minted token after the helper returns it; remove or scope that helper for GitHub if that matters.

### `gh-app-token` uses old values after editing `.env`

Process environment variables win over the file. Interactive shells export `GITHUB_APP_*` from `.env`; run `reload` or open a new shell after editing it.

### Helm still uses the PAT

The post-create `ghcr.io` login is intentionally PAT-backed; installation tokens expire after about an hour. Keep a `GITHUB_TOKEN` with package access or log in manually when needed.

### The prompt shows boxes instead of icons

`starship.toml` uses Nerd Font glyphs. Install a [Nerd Font](https://www.nerdfonts.com/) and select it in your terminal.

### Permission errors on `.local`, `.config`, or `/workspace/repos`

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

The timezone default is a similar static contract: keep `ARG TZ=America/Los_Angeles` and the `${localEnv:DEVCONTAINER_TZ:America/Los_Angeles}` template default in `devcontainer.json` aligned with the static assertion in `test/devcontainer-smoke.sh`; the `pre` and runtime checks derive their expected zone from `ARG TZ` and `TZ`.

## Learn more

- [Development Containers specification](https://containers.dev)
- [Dev Container Features](https://containers.dev/features)
- [Dev Containers CLI](https://github.com/devcontainers/cli)
- [Glow](https://github.com/charmbracelet/glow)
- [OpenCode](https://opencode.ai)
- [Starship](https://starship.rs)
