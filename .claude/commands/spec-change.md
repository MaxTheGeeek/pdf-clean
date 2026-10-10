---
description: Change behaviour the spec-driven way (requirements → tests → tasks before code)
argument-hint: "<what should change>"
---

Requested change: $ARGUMENTS

1. Find the affected requirement(s) in `specs/01-requirements.md` and the related sections in the technical/sanitisation/UI specs. Quote the current text briefly.
2. Check the change against `specs/00-constitution.md`. If it conflicts, stop and explain.
3. Propose the edits: requirement text + acceptance criteria, spec sections, test cases in `specs/05-test-plan.md`, and either a new task in `specs/06-tasks.md` (next free ID in the right phase, with Status/Depends on/Covers/Files/Do/Tests/Done when) or changes to an existing `todo` task. If fixture expectations change, edit `scripts/fixtures/build_manifest.py` (never `manifest.json`) and run `make fixtures && make fixtures-verify`.
4. If the decision is architectural, add `specs/adr/ADR-00N-<slug>.md`.
5. Run `python3 scripts/check_specs.py`. Show me the diff summary and wait for my OK before implementing code.
