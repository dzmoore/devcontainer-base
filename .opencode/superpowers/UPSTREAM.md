# Superpowers

- Source: https://github.com/obra/superpowers
- Release: v7.0.2
- Pinned ref: c62ffea8267a70de07583e153544d355b6748a56 (annotated tag; commit 22f0b463e7a5e579904dd6211a520321035526f7)
- License: MIT
- Copyright (c) 2025 Jesse Vincent

This tree vendors index.js, .opencode/plugins/superpowers.js, skills/,
package.json, and LICENSE from the pinned upstream release.

## Local patch

../superpowers-local.patch applies to the pinned tree. scripts/update-superpowers.sh
applies it before the tree is copied. It:

- adds canonical TDD references and requires explicit user approval for TDD
  exceptions; and
- maps the subagent-driven-development templates to the named implementer and
  validator agents, removes per-dispatch model selection, and states that agent
  files own model selection; and
- maps the injected V1 and V2 tool guidance, the code-review and parallel
  dispatch skills, and the brainstorming builder check to named control-plane
  agents, and forbids dispatching general.

Verify the tree with scripts/update-superpowers.sh --check.
