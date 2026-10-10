# CLAUDE.md — PDFClean

Offline macOS + iOS/iPadOS app (SwiftUI) that turns a PDF into clean, structured text
(title, headings, table of contents, paragraphs, lists) and removes every hidden token,
identifier and piece of metadata. Flow: **Open → Wait → Review → Save** (Markdown/HTML/TXT).

## Read first (source of truth — in this order)
1. `specs/00-constitution.md` — non-negotiable rules (offline, build-don't-copy, permissions, privacy, determinism)
2. `specs/06-tasks.md` — the work plan; pick tasks from here
3. `specs/01-requirements.md` — FR/NFR with acceptance criteria
4. `specs/02-technical-spec.md` — architecture, API, algorithms, constants
5. `specs/03-sanitization-spec.md` — hidden-content rules (most delicate code)
6. `specs/04-ui-spec.md`, `specs/05-test-plan.md`, `specs/adr/*`

Only read the parts a task needs; do not paste whole specs into replies.

## Workflow (spec-driven)
- One task per session: `/next-task` or `/implement-task T-0xx`.
- Order inside a task: re-read the referenced spec sections → write/enable tests → implement → `make verify` → update the task's **Status** in `specs/06-tasks.md` → commit `T-0xx: <title>`.
- Behaviour change not in the spec? Use `/spec-change` first (update requirement, tests, tasks), then code.
- Finish with the `spec-reviewer` agent; for anything under `Sanitize/`, `Extraction/` or `Export/` also run `sanitization-auditor`.

## Commands
| Purpose | Command |
|---------|---------|
| Package build / tests | `make build` · `make test` |
| All gates (must pass before "done") | `make verify` (= check-specs + check-offline + lint + test) |
| Apps | `make generate` (XcodeGen) · `make build-mac` · `make build-ios` · `make test-ios` |
| CLI | `make run-cli ARGS="file.pdf -o out.md --report r.json"` |
| End-to-end over fixtures | `make e2e` |
| Fixtures | `make fixtures` (regenerate) · `make fixtures-verify` (prove they are meaningful) |
| Format | `make format` |

## Layout
- `Packages/PDFCleanKit/Sources/PDFCleanKit/` — all logic: `Model/ Ingest/ Extraction/ Sanitize/ Layout/ Export/ Pipeline/`, `Constants.swift`, `Log.swift`
- `Packages/PDFCleanKit/Sources/pdfclean/` — developer CLI (macOS)
- `Packages/PDFCleanKit/Tests/PDFCleanKitTests/` — `Unit/`, `Fixtures/` (PDFs + `manifest.json`), `Golden/`
- `App/Shared/` — SwiftUI only (state machine + views); no extraction logic in the app target
- `scripts/` — gates, fixture generator/verifier, `reference/visibility_reference.py`

## Hard rules
- **No network, ever**: no URLSession/Network/WebKit/sockets/URL literals; no package dependencies; macOS sandbox without network entitlements. `make check-offline` enforces it.
- **Logging only via `Log.event("name", ("key", intValue))`** — never text, file names, paths or metadata values.
- **Output is built from the document model only**; every export goes through `OutputVerifier`.
- **Never edit `Fixtures/manifest.json` or fixture PDFs by hand** (denied in settings). Change `scripts/fixtures/build_manifest.py` / `generate_fixtures.py`, then `make fixtures && make fixtures-verify`.
- Thresholds live in `Constants.swift` and must match `specs/02-technical-spec.md` §10 and `scripts/reference/visibility_reference.py`. Change all three together, with fixture evidence.
- Swift 6 language mode, strict concurrency. PDFKit/CoreGraphics/Vision objects stay inside the `ExtractionPipeline` actor; everything public is a `Sendable` value type.
- Deterministic output: no dates, UUIDs or randomness in exports; stable sorts with tie-breakers.
- Honour PDF permissions (ADR-004): never bypass encryption or copy restrictions.
- No force unwraps / `try!` in library code; public APIs have `///` docs.

## Gotchas (learned while writing the spec — do not rediscover)
- `PDFPage.characterBounds(at:)` uses **UTF-16 offsets** of `page.string`; surrogate pairs (e.g. TAG characters U+E00xx) span two offsets.
- Zero-width/format characters have **empty boxes** but must stay inside their word ("Visi⟨U+200B⟩ble" is one word). Only whitespace/newlines with empty boxes are separators.
- Rotated watermark glyphs come back as axis-aligned boxes stepping diagonally: detect rotated **runs on glyphs before word building**, or they shatter into single letters.
- `CGContext.drawPDFPage` draws content without annotations (wanted). Bitmap row 0 is the **top** row. Raster test uses unrotated page space; layout uses display space.
- Measuring ink over the full word box leaks neighbour descenders into hidden words (4.5 %); use the exclusive area (spec §3.2). Insetting the box drops `_` and `.` — don't.
- Text render mode is graphics state and persists after `ET` — this is why render-based visibility, not content-stream parsing, is used (ADR-002).
- Invisible OCR text over a scanned image is legitimate and must be kept (ink exists under it).
- A large-font line on every page ("Chapter N") is a heading, not a header/footer or title: margin and repeat rules cap font size.

## Definition of done
Tests for the task's TC IDs exist and pass · `make verify` green · task Status updated ·
spec updated if behaviour changed · no new warnings.
