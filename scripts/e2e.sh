#!/usr/bin/env bash
# TC-E01: run the pdfclean CLI over every fixture in manifest.json and check
# exit codes + mustNotContain. Implemented in task T-040 (specs/06-tasks.md).
#
# Contract for the implementation:
#   - binary: $(swift build --package-path Packages/PDFCleanKit --show-bin-path)/pdfclean
#   - for each manifest case: run with --password (if any) to .build-out/<id>.{md,html,txt}
#     and --report .build-out/<id>.json
#   - expectError -> exit code per FR-24; success -> exit 0 and no mustNotContain /
#     mustNotContainDerived string in any output file
#   - print one line per case and a summary; exit 1 on any failure
set -euo pipefail
cd "$(dirname "$0")/.."
echo "e2e: not implemented yet (task T-040)"
exit 0
