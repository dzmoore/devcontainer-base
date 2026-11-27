# Spec Delta

## ADDED Requirements

### Requirement: OpenSpec CLI is image-provided and version-pinned
The image SHALL install OpenSpec `2.1.1` from the official standalone release into `/usr/local/bin`, verifying the per-architecture SHA-256. The CLI SHALL NOT depend on the nvm-managed Node.js, and `post-create.sh` SHALL verify the pinned version instead of installing it.

#### Scenario: Image build installs the pinned CLI
- **WHEN** the image is built
- **THEN** `openspec --version` reports `2.1.1` and the downloaded tarball matched its architecture-specific SHA-256

#### Scenario: Post-create verifies without npm, curl, or Node
- **WHEN** `post-create.sh` runs in a clean container
- **THEN** it verifies OpenSpec `2.1.1` with the image binary and does not invoke npm, curl, or Node on the OpenSpec path

#### Scenario: OpenSpec runs without the nvm Node.js
- **WHEN** `openspec --version` runs with a clean environment that does not include the nvm `PATH`
- **THEN** it still reports `2.1.1`
