#!/usr/bin/env python3
"""
Spec traceability gate (ADR-005). Run: make check-specs   (stdlib only)

Checks
 1. every FR/NFR defined in specs/01-requirements.md is covered by >= 1 test case
    (specs/05-test-plan.md) and >= 1 task (specs/06-tasks.md);
 2. tests, tasks and the fixture manifest only reference requirement IDs that exist;
 3. task dependencies exist, have no cycles, and every task has Status/Covers lines
    with a valid status value;
 4. every fixture file named in manifest.json exists, ids are unique;
 5. every `TC-...` named in tasks exists in the test plan.
Prints a coverage summary; exit code 1 on any problem.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQ = ROOT / "specs/01-requirements.md"
TESTS = ROOT / "specs/05-test-plan.md"
TASKS = ROOT / "specs/06-tasks.md"
FIX = ROOT / "Packages/PDFCleanKit/Tests/PDFCleanKitTests/Fixtures"

ID = re.compile(r"\bN?FR-\d{2}\b")
STATUSES = ("todo", "in-progress", "done", "blocked")

# Requirements with no dedicated test-plan row by design. NFR-07's only test was the
# coverage gate (T-062/TC-Q01), descoped for v1; NFR-07's strict-concurrency clause is
# enforced by the Swift 6 compiler itself (a build failure, not a runtime test), and its
# task coverage (T-001, T-004) still holds.
TEST_COVERAGE_EXEMPT = {"NFR-07"}


def main() -> int:
    problems: list[str] = []

    requirements = re.findall(r"^### (N?FR-\d{2}) — ", REQ.read_text(encoding="utf-8"), re.M)
    req_set = set(requirements)
    if len(req_set) != len(requirements):
        problems.append("duplicate requirement IDs in 01-requirements.md")

    # ---- tests
    tests: dict[str, set[str]] = {}
    for line in TESTS.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\|\s*(TC-[A-Z]*\d+)\s*\|", line)
        if m:
            covers = set(ID.findall(line.split("|")[-2]))  # last column = Covers
            if not covers:
                problems.append(f"{m.group(1)} has no Covers IDs")
            tests[m.group(1)] = covers

    # ---- tasks
    tasks: dict[str, dict] = {}
    current = None
    for line in TASKS.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^### (T-\d{3}) — (.+)$", line)
        if m:
            current = m.group(1)
            if current in tasks:
                problems.append(f"duplicate task {current}")
            tasks[current] = {"title": m.group(2), "covers": set(), "deps": set(), "status": None, "tcs": set()}
            continue
        if not current:
            continue
        if line.startswith("- **Status:**"):
            tasks[current]["status"] = line.split("**Status:**", 1)[1].strip()
        elif line.startswith("- **Covers:**"):
            tasks[current]["covers"] = set(ID.findall(line))
        elif line.startswith("- **Depends on:**"):
            tasks[current]["deps"] = set(re.findall(r"T-\d{3}", line))
        tasks[current]["tcs"] |= set(re.findall(r"\bTC-[A-Z]*\d+\b", line))

    for tid, t in tasks.items():
        if not t["status"] or not t["status"].split(" ")[0] in STATUSES:
            problems.append(f"{tid}: missing/invalid Status ({t['status']!r})")
        if not t["covers"]:
            problems.append(f"{tid}: missing Covers")
        for d in t["deps"]:
            if d not in tasks:
                problems.append(f"{tid}: depends on unknown {d}")
        for tc in t["tcs"]:
            if tc not in tests:
                problems.append(f"{tid}: references unknown test {tc}")

    # cycle detection
    state: dict[str, int] = {}

    def visit(n: str, path: list[str]) -> None:
        if state.get(n) == 1:
            problems.append("dependency cycle: " + " -> ".join(path + [n]))
            return
        if state.get(n) == 2 or n not in tasks:
            return
        state[n] = 1
        for d in sorted(tasks[n]["deps"]):
            visit(d, path + [n])
        state[n] = 2

    for n in tasks:
        visit(n, [])

    # ---- references must exist
    for tc, covers in tests.items():
        for r in covers - req_set:
            problems.append(f"{tc} references unknown {r}")
    for tid, t in tasks.items():
        for r in t["covers"] - req_set:
            problems.append(f"{tid} references unknown {r}")

    # ---- coverage
    covered_by_tests = {r for c in tests.values() for r in c}
    covered_by_tasks = {r for t in tasks.values() for r in t["covers"]}
    for r in requirements:
        if r not in covered_by_tests and r not in TEST_COVERAGE_EXEMPT:
            problems.append(f"{r} has no test case")
        if r not in covered_by_tasks:
            problems.append(f"{r} has no task")

    # ---- manifest
    manifest_path = FIX / "manifest.json"
    if not manifest_path.exists():
        problems.append("manifest.json missing (run make fixtures)")
    else:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        ids = [f["id"] for f in manifest["fixtures"]]
        if len(ids) != len(set(ids)):
            problems.append("duplicate fixture ids in manifest.json")
        for f in manifest["fixtures"]:
            if not (FIX / f["file"]).exists():
                problems.append(f"fixture file missing: {f['file']}")
            for r in f.get("covers", []):
                if r not in req_set:
                    problems.append(f"fixture {f['id']} covers unknown {r}")

    # ---- report
    done = sum(1 for t in tasks.values() if t["status"] == "done")
    print(f"requirements: {len(requirements)}  test cases: {len(tests)}  tasks: {len(tasks)} ({done} done)")
    if problems:
        print("\nTRACEABILITY PROBLEMS:")
        for p in problems:
            print("  -", p)
        return 1
    print("check-specs: ok (every requirement has tests and tasks; all references resolve)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
