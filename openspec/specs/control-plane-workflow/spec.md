# control-plane-workflow Specification

## Purpose

Defines how the control plane turns an approved change into tested code through named subagents and independent gates.

## Requirements

### Requirement: Orchestrator owns the lifecycle
The orchestrator SHALL own intake, design approval, planning, delegation, validation, and the final report. It SHALL NOT delegate control of the workflow to OpenSpec or to an implementer.

#### Scenario: A new change enters the workflow
- **WHEN** the user requests a change and approves its design
- **THEN** the orchestrator creates or selects the OpenSpec change and drives it through proposal, tasks, implementation, validation, and archive.

### Requirement: One implementer per task
The orchestrator SHALL dispatch one implementer per task and SHALL NOT run two implementers concurrently on shared files.

#### Scenario: Two ready tasks touch the same module
- **WHEN** two tasks modify the same files
- **THEN** the orchestrator runs them sequentially.

### Requirement: Implementer provides RED and GREEN evidence
The implementer SHALL write a failing test first, record the RED command and failure, then make the smallest change that passes and record the GREEN command and result.

#### Scenario: A task changes behavior
- **WHEN** the implementer starts a task with observable behavior
- **THEN** the task report contains the failing test, the RED output, and the passing GREEN output.

### Requirement: Validator is independent
The validator SHALL rerun the relevant tests and review the diff against the acceptance criteria. It SHALL NOT accept the implementer's report as evidence.

#### Scenario: Implementer reports a passing task
- **WHEN** the implementer reports GREEN
- **THEN** the validator reruns the focused and full suites and returns PASS or FAIL with command output.

### Requirement: Security review precedes completion
The security-reviewer SHALL review the final tree and host configuration before the orchestrator reports completion.

#### Scenario: Final gate
- **WHEN** all tasks have passed validation
- **THEN** the security-reviewer reviews the branch and the orchestrator reports its verdict.
