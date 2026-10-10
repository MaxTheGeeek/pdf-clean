---
description: Implement one task from specs/06-tasks.md (spec → tests → code → verify → status)
argument-hint: T-0xx
---

Implement task **$ARGUMENTS** from `specs/06-tasks.md`.

1. **Load context** — read the task block, then only the spec sections it references (requirements by FR/NFR ID, technical spec sections, sanitisation spec sections, test cases by TC ID). Re-read `specs/00-constitution.md` if the task touches Ingest, Extraction, Sanitize, Export or the app's file handling.
2. **Check dependencies** — every task in *Depends on* must be `done`. If not, stop and say which.
3. **Set status** — change the task's Status line to `in-progress`.
4. **Tests first** — create or enable the tests listed under *Tests* (Swift Testing, `@Test`, `#expect`/`#require`). Use synthetic inputs for pure logic and the fixture manifest for pipeline behaviour. Run `make test` and confirm the new tests fail for the right reason.
5. **Implement** — only the files listed (plus obviously necessary helpers). Follow the spec's names, types, constants (`Constants.swift`) and order of operations. Keep heuristics as pure functions.
6. **Verify** — run `make verify`. Fix until green. For app tasks also run `make build-mac` and `make build-ios`.
7. **Spec drift** — if the implementation revealed that the spec is wrong or incomplete, update the spec in the same change and say so explicitly. Never silently diverge.
8. **Finish** — set Status to `done`, then commit: `T-0xx: <title>`. Report in ≤ 10 lines: what was built, tests added (TC IDs), any spec changes, follow-ups.

Do not start the next task in the same session unless I ask.
