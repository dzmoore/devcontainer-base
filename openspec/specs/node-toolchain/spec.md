# node-toolchain Specification

## Purpose

Defines how Node.js is provisioned inside the devcontainer image and what the developer user can rely on after the image is built.

## Requirements

### Requirement: Node.js is installed from pinned nvm and Node releases
The image SHALL install nvm `v0.41.0` and Node.js `26.13.1` during the build in the developer user's home directory. It SHALL verify the nvm install script against a pinned SHA-256, enable the `$NVM_DIR/current` symlink, and set `NVM_NO_SOURCE_FALLBACK` so a download failure stops the build instead of compiling Node from source.

#### Scenario: Image build installs the pinned toolchain
- **WHEN** the image is built
- **THEN** `node --version` reports `26.13.1`, `nvm --version` reports `0.41.0`, and the build fails if the nvm install script does not match its pinned SHA-256

#### Scenario: Node binary download fails
- **WHEN** nvm cannot download the pinned Node.js binary
- **THEN** the build fails instead of falling back to a source compile

### Requirement: Node.js is available in non-interactive and login shells
The image SHALL put `node`, `npm`, and `npx` on `PATH` for `sh -c`, `bash -c`, `sh -lc`, and `bash -lc` commands, and interactive bash SHALL also expose the `nvm` command.

#### Scenario: Non-interactive command resolves Node.js
- **WHEN** a command runs through `sh -c`, `bash -c`, or the devcontainer `postCreateCommand`
- **THEN** `node --version`, `npm --version`, and `npx --version` resolve the pinned Node.js

#### Scenario: Login shell resolves Node.js and nvm
- **WHEN** a login shell runs `node --version` or `nvm --version`
- **THEN** both commands resolve without sourcing a file by hand

#### Scenario: Interactive non-login bash exposes nvm
- **WHEN** an interactive non-login bash runs `nvm --version`
- **THEN** nvm reports `0.41.0` without sourcing a file by hand

### Requirement: Global npm installs work without sudo
The developer user SHALL be able to run `npm install -g` without sudo, and the npm global prefix SHALL resolve inside the nvm-owned directory.

#### Scenario: Developer installs a global package
- **WHEN** the developer user runs `npm install -g <package>`
- **THEN** the install succeeds without sudo and writes under `$NVM_DIR`

#### Scenario: Global prefix points at the nvm install
- **WHEN** the developer user runs `npm prefix -g` and `npm root -g`
- **THEN** both paths resolve under `$NVM_DIR/versions/node/v26.13.1`

### Requirement: The nvm tree survives a container user-ID remap
The nvm tree SHALL remain writable by the runtime user after the container remaps the developer user to a different UID.

#### Scenario: Global install after a UID remap
- **WHEN** the container runs as a remapped UID and the runtime ownership repair has run
- **THEN** `node --version` and `npm install -g` still succeed without sudo

### Requirement: Native npm module builds have a compiler toolchain
The image SHALL provide `make`, `gcc`, `g++`, and C library headers so packages with native addons can build during `npm install` without installing packages at runtime.

#### Scenario: Native addon build
- **WHEN** a package with a native addon is installed
- **THEN** its `node-gyp` build completes with the image's compiler toolchain

### Requirement: pnpm is not preinstalled
The image SHALL NOT preinstall pnpm. The migration documentation SHALL state that pnpm was removed and that `npm install -g pnpm` restores it.

#### Scenario: Fresh container has no pnpm
- **WHEN** a user runs `pnpm --version` in a fresh container
- **THEN** the command is not found

#### Scenario: User needs pnpm
- **WHEN** a user follows the migration note
- **THEN** `npm install -g pnpm` installs pnpm under the nvm global prefix
