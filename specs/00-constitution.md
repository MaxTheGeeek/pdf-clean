# 00 · Constitution — non-negotiable principles

These rules override every other document. If a task, spec or prompt conflicts with
them, stop and raise the conflict instead of implementing.

## P1 — Offline, always
- The app never opens a network connection. No `URLSession`, `Network.framework`,
  `WKWebView`, sockets, analytics, crash reporters, remote config, update checks or
  "phone home" of any kind.
- The macOS target ships with App Sandbox **without** `com.apple.security.network.client`
  / `network.server`, so the OS enforces this.
- All processing uses on-device Apple frameworks: PDFKit, CoreGraphics, Vision,
  NaturalLanguage, UniformTypeIdentifiers, SwiftUI. **No third-party runtime dependencies.**
- `make check-offline` must pass on every commit.

## P2 — Output contains only visible document text
- The output is *built* from text that a human can see on the page. Nothing is
  *copied* from the source file: no Info dictionary, XMP, document ID, annotations,
  form fields, attachments, JavaScript, bookmarks' hidden targets or file names.
- Hidden text (invisible, white-on-white, covered, clipped, off-page, tiny,
  rotated watermarks) and invisible/steganographic Unicode never reach the output.
- Every exported string passes `OutputVerifier` before it is written. A failed
  verification is a bug and blocks the export.

## P3 — Respect document permissions
- Encrypted PDFs are opened only with the password the user supplies.
- If the PDF disallows copying (`allowsCopying == false`), extraction is refused unless
  the user unlocks it with the owner password. The app never bypasses DRM or
  encryption.

## P4 — Privacy by default
- No persistence of documents, extracted text, file names or history between launches.
- Temporary copies live in the app's temporary directory and are deleted when the
  job ends, on cancel and at next launch.
- Logs (`os.Logger`) contain only counts, timings and error codes — never document
  text, file names or metadata values.

## P5 — Deterministic and testable
- Same input + same options ⇒ byte-identical output. No dates, UUIDs or random
  values in outputs; stable sorts with explicit tie-breakers.
- All heuristics live in `PDFCleanKit` as pure, unit-testable functions with named
  constants (no magic numbers inline). Thresholds change only together with fixture
  evidence.
- Spec first: behaviour changes start in `specs/`, then tests, then code.

## P6 — Simple for the user
- One flow: **Open → Wait → Review → Save.** Sensible defaults; options are optional.
- Errors explain what happened and what to do next, in plain language.
