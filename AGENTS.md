# AGENTS.md

## Purpose

This repository may be worked on by humans and AI coding agents.  
This document defines the operational expectations, conventions, and guardrails for contributors and autonomous agents.

Agents should prioritize:
1. Correctness
2. Maintainability
3. Minimal, focused changes
4. Clear reasoning and documentation
5. Safety and reversibility

---

# Repository Principles

## Core Rules

- Do not rewrite large sections unnecessarily.
- Prefer incremental changes over broad refactors.
- Preserve existing architecture unless explicitly instructed otherwise.
- Avoid introducing new dependencies unless justified.
- Keep implementations simple and readable.
- Match existing code style and conventions.
- Favor explicitness over cleverness.

---

# Agent Workflow

## Before Making Changes

Agents should:

1. Read relevant files fully before editing.
2. Understand local patterns and conventions.
3. Search for existing utilities before creating new ones.
4. Check for related tests.
5. Identify configuration, environment, or deployment implications.

## While Making Changes

Agents should:

- Keep diffs focused and minimal.
- Avoid unrelated formatting changes.
- Update documentation when behavior changes.
- Add or update tests when appropriate.
- Preserve backward compatibility unless instructed otherwise.

## After Making Changes

Agents should:

1. Run relevant tests if available.
2. Run linting/formatting if configured.
3. Verify imports/builds/type checks pass when applicable.
4. Summarize:
   - what changed
   - why it changed
   - any tradeoffs or follow-up work

---

# Code Style Expectations

## General

- Write self-documenting code.
- Prefer small, composable functions.
- Avoid deep nesting.
- Use descriptive variable and function names.
- Minimize hidden side effects.

## Comments

Add comments only when necessary to explain:
- intent
- constraints
- non-obvious decisions

Do not add redundant comments describing obvious code behavior.

## Logging

- Keep logs concise and actionable.
- Never log secrets or sensitive data.

---

# Testing Guidelines

## Preferred Approach

- Test behavior, not implementation details.
- Keep tests deterministic.
- Reuse existing test helpers and fixtures.
- Cover happy paths and important edge cases.

## Avoid

- Brittle timing-based tests
- Excessive mocking
- Copy-pasted test setups

---

# Dependency Policy

Before adding a dependency, agents should consider:

- Is this already solved in the repository?
- Can the standard library handle this?
- Is the dependency actively maintained?
- Does it significantly increase complexity or bundle size?

Document the rationale for any new dependency.

---

# Security Guidelines

Agents must:

- Never commit secrets, credentials, or tokens.
- Avoid introducing vulnerabilities through:
  - unsanitized input
  - unsafe eval/execution
  - insecure deserialization
  - command injection
- Use least-privilege principles.
- Validate external input.

If a change may affect security, explicitly mention it.

---

# Configuration Rules

- Prefer environment variables for configuration.
- Document new environment variables.
- Provide sensible defaults when possible.
- Avoid hardcoded machine-specific paths.

---

# Documentation Expectations

Update documentation when changing:

- setup steps
- developer workflows
- public APIs
- configuration
- architectural behavior

Relevant docs may include:
- `README.md`
- `/docs`
- inline code docs
- examples
- changelogs

---

# Git & Commit Guidance

## Repository Structure

> This section is intentionally lightweight in the template repository.
> Projects should customize it as the architecture evolves.

```text
/
├── src/                # Application source code
├── tests/              # Automated tests
├── docs/               # Project documentation
├── scripts/            # Utility and automation scripts
├── config/             # Configuration files/templates
├── examples/           # Example usage or sample apps
├── assets/             # Static assets
├── .github/            # CI/CD and GitHub workflows
└── README.md           # Project overview and setup
```

## Commit Style

Prefer concise, descriptive commits.

Examples:

- `fix auth token refresh race condition`
- `add retry handling for webhook delivery`
- `refactor cache invalidation logic`

## Pull Requests

All changes must go through a Pull Request (PR).

PRs should:

- stay focused on a single concern
- include a clear summary
- explain rationale for non-obvious decisions
- mention testing performed
- note follow-up work if applicable

PR descriptions should include:

- summary of changes
- motivation
- testing performed
- screenshots/examples if UI-related
- known limitations or follow-ups


## Branching

Agents must NEVER work directly on the default branch.

Before making changes:

1. Create a new branch from the latest default branch.
2. Use a descriptive branch name.

Examples:

- `fix/auth-token-refresh`
- `feature/add-webhook-retries`
- `docs/update-install-guide`

## Protected Branches

Agents must NOT:

- push directly to `main` or `master`
- force-push protected branches
- rewrite shared branch history
- bypass branch protection or review requirements

## Commit Practices

Prefer small, logical commits over large monolithic commits.

Avoid:

- unrelated formatting-only commits
- mixing refactors with behavior changes
- autogenerated noise unless necessary

## Rebasing & Merging

Agents should:

- prefer clean, understandable history
- avoid destructive rebases on shared branches
- sync with the default branch before opening PRs if needed

## CI/CD Expectations

Before requesting merge, agents should:

- run relevant tests
- run linting/formatting if configured
- verify builds/type-checks pass where applicable

If something cannot be verified locally, explicitly state that.

## Human Review

Human review is required before:

- merging PRs
- releasing to production
- modifying infrastructure
- changing security-sensitive code
- performing destructive migrations

## Large Changes

For substantial refactors or architecture changes:

1. Open an issue/discussion first if applicable.
2. Break work into smaller reviewable PRs.
3. Preserve backward compatibility when possible.

## Auditability

Agents should maintain clear traceability between:

- issue/task
- branch
- commits
- PR description
- resulting change

---

# Architecture Guidance

Unless instructed otherwise:

- Preserve public interfaces.
- Avoid unnecessary abstractions.
- Prefer composition over inheritance.
- Keep modules cohesive.
- Minimize coupling between layers.

---

# Performance Expectations

Agents should:

- Avoid premature optimization.
- Consider performance for hot paths.
- Avoid unnecessary allocations/network calls.
- Preserve scalability characteristics of existing systems.

Call out meaningful performance tradeoffs.

---

# AI-Agent Specific Instructions

## Allowed Actions

Agents may:
- read files
- modify files
- create files
- run local analysis/testing commands
- propose refactors

## Disallowed Actions

Agents must NOT:
- delete large sections without justification
- overwrite user work unexpectedly
- introduce breaking changes silently
- fabricate test results
- assume undocumented behavior as fact

## Decision Making

When requirements are ambiguous:
- prefer conservative implementations
- document assumptions
- avoid hidden magic

When multiple valid approaches exist:
- choose the simplest maintainable solution

---

# Preferred Change Characteristics

Good changes are:

- small
- reviewable
- tested
- documented
- reversible

---

# Escalation Conditions

Agents should request human review when:

- security implications are unclear
- migrations may cause data loss
- architecture changes are substantial
- requirements conflict
- production impact is uncertain

---

# Repository Overrides

Project-specific instructions may override this file.

Potential override locations:

- `/docs/`
- `.github/`
- language-specific config files
- nested `AGENTS.md` files

The most specific applicable instruction takes precedence.

---

# Final Checklist

Before completing work, agents should verify:

- [ ] Changes are scoped appropriately
- [ ] Code follows repository conventions
- [ ] Tests pass or limitations are documented
- [ ] Documentation is updated if needed
- [ ] No secrets or sensitive data were introduced
- [ ] Changes are explainable and reviewable
