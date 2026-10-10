# ADR-005 · Spec-driven development with Claude Code

**Status:** Accepted · **Date:** 2026-10-10

## Context
The app is built with Claude Code (CLI and VS Code extension). Heuristic code drifts
easily without hard acceptance criteria.

## Decision
- `specs/` is the source of truth; `CLAUDE.md` points every session at it.
- Requirements have IDs; tests and tasks reference them; `make check-specs` enforces
  traceability (every FR/NFR has ≥ 1 test case and ≥ 1 task).
- Fixture expectations are generated (`build_manifest.py`) and independently validated
  (`verify_fixtures.py`, `visibility_reference.py`) before Swift code relies on them.
- Work proceeds one task at a time through `/next-task` and `/implement-task`, ending
  with `/verify` and a review by the `spec-reviewer` agent.

## Consequences
+ Each session has a bounded scope and an objective "done".
− Spec edits are required before behaviour changes (intentional friction).
