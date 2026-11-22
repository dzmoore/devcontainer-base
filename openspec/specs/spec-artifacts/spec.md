# spec-artifacts Specification

## Purpose

Defines the OpenSpec artifact lifecycle and the boundary between OpenSpec verification and the control plane's validation gates.

## Requirements

### Requirement: OpenSpec root is explicit
The control plane SHALL require an existing `openspec/` root before creating a change. It SHALL NOT create the root as a side effect.

#### Scenario: Target repository is not initialized
- **WHEN** the orchestrator finds no `openspec/` root
- **THEN** it stops and asks the user to run `openspec init` or to choose another approach.

### Requirement: Change artifacts follow the schema
Each change SHALL contain a proposal, delta specs for every declared capability, a design when the change is architectural or cross-cutting, and a task list.

#### Scenario: Propose a change
- **WHEN** the user requests a new capability
- **THEN** the change folder contains `proposal.md`, `specs/<capability>/spec.md`, `design.md` when required, and `tasks.md`.

### Requirement: Living specs are updated on archive
Archiving a completed change SHALL fold its delta specs into the living specs under `openspec/specs/`.

#### Scenario: Completed change is archived
- **WHEN** validation passes and the change is archived
- **THEN** the living specs reflect the added, modified, or removed requirements.

### Requirement: OpenSpec verification is advisory
OpenSpec verification SHALL NOT replace the validator. A passing OpenSpec verification without a passing validator and test suite SHALL NOT count as completion.

#### Scenario: OpenSpec verify passes but tests fail
- **WHEN** OpenSpec verification reports success and the validator reports FAIL
- **THEN** the change remains incomplete.

### Requirement: Generated skills are Markdown only
OpenSpec initialization SHALL install Markdown skills under `.agents/skills/` and SHALL NOT introduce a plugin, runtime hook, or vendored script tree.

#### Scenario: Initialize a repository
- **WHEN** `openspec init --tools opencode` completes
- **THEN** the repository contains `openspec/` and Markdown skills under `.agents/skills/`, with no plugin file.
