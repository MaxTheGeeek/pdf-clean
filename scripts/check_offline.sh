#!/usr/bin/env bash
# Gate for NFR-01 (offline) and NFR-02 (privacy). Run: make check-offline
# Fails when Swift sources use network APIs, web views or URL literals, when the
# macOS target gains a network entitlement, when the package gains dependencies,
# or when code logs through anything other than PDFCleanKit's `Log.event`.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
note() { printf '  ✗ %s\n' "$1"; fail=1; }

SWIFT_DIRS=(App Packages/PDFCleanKit/Sources)

# 1. Network APIs, web views, sockets, URL literals
NET='\bURLSession\b|\bURLRequest\b|\bURLSessionConfiguration\b|import[[:space:]]+Network\b|\bNWConnection\b|\bNWPathMonitor\b|import[[:space:]]+WebKit\b|\bWKWebView\b|\bCFStream[A-Za-z]*\b|\bCFHTTP[A-Za-z]*\b|\bsocket\(|\bgetaddrinfo\b|https?://'
if grep -RInE --include='*.swift' "$NET" "${SWIFT_DIRS[@]}"; then
  note "network API, web view or URL literal in Swift sources (constitution P1)"
fi

# 2. Entitlements: sandbox on, no network keys
for f in App/macOS/PDFClean.entitlements project.yml; do
  if grep -n 'com.apple.security.network' "$f"; then note "network entitlement in $f"; fi
done
grep -q 'com.apple.security.app-sandbox' App/macOS/PDFClean.entitlements || note "App Sandbox missing in entitlements"

# 3. No third-party package dependencies
if grep -nE '\.package\(' Packages/PDFCleanKit/Package.swift; then
  note "Package.swift declares a dependency (constitution P1: Apple frameworks only)"
fi

# 4. Logging only via Log.event (no print/NSLog/os_log/Logger elsewhere; CLI may print)
LOG='\bprint\(|\bdebugPrint\(|\bNSLog\(|\bos_log\(|\bLogger\('
if grep -RInE --include='*.swift' "$LOG" App Packages/PDFCleanKit/Sources/PDFCleanKit | grep -v 'Sources/PDFCleanKit/Log.swift'; then
  note "logging outside Log.event (constitution P4)"
fi

# 5. No persistence of document data (UserDefaults/AppStorage allowed for options only, reviewed manually)
if grep -RInE --include='*.swift' '\bFileManager\.default\.urls\(for: *\.(documentDirectory|applicationSupportDirectory)' App Packages/PDFCleanKit/Sources; then
  note "writes to Documents/Application Support (constitution P4: temp directory only)"
fi

if [[ $fail -ne 0 ]]; then
  echo "check-offline: FAILED"; exit 1
fi
echo "check-offline: ok"
