---
description: Run all quality gates and explain any failure
allowed-tools: Bash(make verify) Bash(make e2e) Bash(make build-mac) Bash(make build-ios)
---

Run `make verify`. If the app targets changed in this branch (`git diff --name-only main` touches `App/` or `project.yml`), also run `make build-mac` and `make build-ios`. If the CLI exists (task T-040 done), run `make e2e`.

Report a table: gate · result · first failure line. For each failure, identify the cause and propose (or, if it is clearly within the current task, apply) the fix. Never weaken a gate, delete a test, or edit `Fixtures/manifest.json` to make something pass.
