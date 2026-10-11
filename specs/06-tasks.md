# 06 · Tasks

How to use (Claude Code): `/next-task` picks the first task whose status is `todo` and
whose dependencies are `done`; `/implement-task T-0xx` implements one task. Each task
fits one session, ends green (`make verify`), and updates its **Status** line here.
Status values: `todo` · `in-progress` · `done` · `blocked (<reason>)`.

Definition of Done (every task)
1. Code follows the specs; any spec change is made in `specs/` first, in the same commit.
2. Tests listed under **Tests** exist and pass; `make verify` is green.
3. No network APIs; no logging of content (constitution P1, P4).
4. Public API documented with `///` comments; constants in `Constants.swift`.
5. Task status updated; one commit per task: `T-0xx: <title>`.

---

## Phase 0 — Foundation

### T-001 — Verify scaffold and toolchain
- **Status:** done
- **Depends on:** —
- **Covers:** NFR-04, NFR-07
- **Files:** `Packages/PDFCleanKit/Package.swift`, `project.yml`, `App/Shared/*`, `Makefile`
- **Do:** `make bootstrap && make generate && make build && make test && make build-mac && make build-ios`. Fix anything that fails in the scaffold. Add `.swift-format` config and `make format`/`make lint`.
- **Tests:** existing smoke test passes.
- **Done when:** all six commands succeed on a clean clone.

### T-002 — Static gates
- **Status:** done
- **Depends on:** T-001
- **Covers:** NFR-01, NFR-02
- **Files:** `scripts/check_offline.sh`, `scripts/check_specs.py`, `scripts/e2e.sh` (stub), `Makefile`
- **Do:** make sure `make verify` = check-specs + check-offline + lint + test. The log-hygiene rule (TC-E03) is already in `check_offline.sh` (logging only via `Log.event`); keep it.
- **Tests:** TC-E02, TC-E03.
- **Done when:** gates fail on a planted `URLSession` line and on a planted `print(text)`, and pass when removed.

### T-003 — Fixture harness skeleton
- **Status:** done
- **Depends on:** T-001
- **Covers:** FR-02
- **Files:** `Tests/PDFCleanKitTests/FixtureManifest.swift`, `Tests/PDFCleanKitTests/FixtureSuiteTests.swift`
- **Do:** Codable model for `manifest.json` (all fields of test plan §2), loader via `Bundle.module`, parameterised `@Test(arguments:)` over fixture ids. Until the pipeline exists, cases record a known issue ("pipeline pending") via `withKnownIssue` except the `notAPDF` header check.
  - *Spec drift found during implementation:* the files cannot live under `Tests/PDFCleanKitTests/Fixtures/` as originally written — `Package.swift`'s `.copy("Fixtures")` resource rule claims that whole directory, so SwiftPM copies any `.swift` file placed there as an inert resource instead of compiling it (confirmed: it ended up as plain bytes inside the test bundle, absent from `swift package describe`'s source list). Moved both files to `Tests/PDFCleanKitTests/` directly, matching CLAUDE.md's own Layout note ("Fixtures/ (PDFs + manifest.json)" only).
  - *Spec drift found during implementation:* `.disabled(...)` on a parameterised `@Test` skips the whole test before expanding arguments — Swift Testing reports one skipped test, not 14 — so "the suite lists 15 cases" is unreachable with that trait. Used `withKnownIssue(...)` inside the body instead: all 14 pending arguments still expand and run individually (visible in `swift test` output as separate cases), the suite stays green, and the signal "not implemented yet" is preserved via the known-issue annotation.
- **Tests:** TC-F01 (skeleton).
- **Done when:** the suite lists 15 cases; manifest decodes without loss (round-trip test).

### T-004 — Core model, options, errors, constants
- **Status:** done
- **Depends on:** T-001
- **Covers:** FR-19, NFR-07, NFR-09
- **Files:** `Model/*.swift`, `Pipeline/PipelineError.swift`, `Constants.swift`
- **Do:** implement tech spec §4–5 types exactly (Sendable, Equatable, Codable), `Constants` table §10.
- **Tests:** Codable round-trip; `SanitizationReport` KeyPath table used by the harness.
- **Done when:** types compile in Swift 6 mode with no warnings.
  - *Spec gap filled during implementation:* `PipelineError.outputVerificationFailed([OutputViolation])` references a type the spec never defines (`OutputViolation` only appears as a name in §4/§6.11). Added a minimal `OutputViolation` enum next to `PipelineError` in `Pipeline/PipelineError.swift` with the four categories §6.11 names (forbidden code point, non-ASCII space, C0 control, metadata value leak) so the model compiles; flagged for review when `OutputVerifier` is implemented (T-014), since its real checks may need different associated data.
  - *Spec drift found during implementation:* the tech spec's `SanitizationReport` "KeyPath table" can't be a stored `static let [String: KeyPath<...>]` — `KeyPath` is not `Sendable`, so Swift 6 strict concurrency rejects it as shared mutable global state. Implemented as `SanitizationReport.counterKeyPath(named:) -> KeyPath<SanitizationReport, Int>?`, a pure function with the same name-to-property mapping, computed fresh per call instead of stored.

## Phase 1 — Pure text processing (no PDFKit)

### T-010 — UnicodeSanitizer
- **Status:** done
- **Depends on:** T-004
- **Covers:** FR-14, FR-15
- **Files:** `Sanitize/UnicodeSanitizer.swift`, `Sanitize/UnicodeTables.swift`
- **Do:** sanitisation spec §6 incl. context exceptions §6.1 (use `Unicode.Scalar.Properties` for general category and script via `Character`/`Unicode.Scalar` APIs; keep the script table small and explicit).
- **Tests:** TC-U01, TC-U02, TC-U03, TC-U04.
- **Done when:** all listed tests pass; function is pure and returns counters.

### T-011 — HomoglyphNormalizer
- **Status:** done
- **Depends on:** T-010
- **Covers:** FR-15
- **Files:** `Sanitize/HomoglyphNormalizer.swift`
- **Do:** sanitisation spec §7.
- **Tests:** TC-U05.
- **Done when:** mixed tokens normalised, pure-script tokens untouched.

### T-012 — IdentifierDetector and redaction
- **Status:** done
- **Depends on:** T-004
- **Covers:** FR-18
- **Files:** `Sanitize/IdentifierDetector.swift`
- **Do:** tech spec §6.9.
- **Tests:** TC-U06.
- **Done when:** positives/negatives pass; findings deterministic order.
  - Note: this task implements detection only (`IdentifierDetector.detect`). The actual
    `[REDACTED]` substitution at render time (`ExportOptions.redactedIdentifiers`) is
    T-013's job, per its own Do line ("redaction at render time").

### T-013 — Renderers
- **Status:** done
- **Depends on:** T-004, T-012
- **Covers:** FR-21, FR-17, FR-18
- **Files:** `Export/MarkdownRenderer.swift`, `HTMLRenderer.swift`, `PlainTextRenderer.swift`, `DocumentExporter.swift`, `Export/Resources/print.css` (embedded as a string constant)
- **Do:** tech spec §6.10, redaction at render time, suggested file names.
- **Tests:** TC-U07, TC-U08, TC-U09, TC-U10, TC-U12.
- **Done when:** golden files in `Tests/.../Golden/` match byte for byte.
  - *Spec drift found during implementation:* `Export/Resources/print.css` is a Swift file
    (`PrintCSS.swift`, a string constant), not a literal `.css` resource — same reasoning
    as T-003's drift note: the HTML export must stay self-contained offline, and a real
    resource file would need `Package.swift` resource wiring that doesn't mix with
    compiled sources in the same directory.
  - *Interpretation:* "blocks separated by exactly one blank line" is applied per
    semantic group, not per `[Block]` array element — a run of consecutive `listItem`
    blocks (same ordered-ness) renders as one unbroken list with no blank lines between
    its own items (otherwise Markdown would parse each item as a separate list).
  - `DocumentExporter.render` does not yet call `OutputVerifier` — that gate is T-014's
    job per its own Do line.
  - Golden tests live alongside their renderer tests in `Tests/.../Unit/` (hardcoded
    expected strings in test code) rather than separate files under `Tests/.../Golden/`;
    `Golden/README.txt` predates this and the directory stays unused for now.

### T-014 — OutputVerifier and CleanFileWriter
- **Status:** todo
- **Depends on:** T-010
- **Covers:** FR-22, FR-21
- **Files:** `Export/OutputVerifier.swift`, `Export/CleanFileWriter.swift`
- **Do:** tech spec §6.11; `DocumentExporter.render` calls the verifier and throws on violations; writer strips xattrs on macOS (ignore EPERM).
- **Tests:** TC-U11; writer test checks no BOM, LF only, final newline, xattrs removed (macOS).
- **Done when:** tests pass on macOS and iOS simulator.

## Phase 2 — Layout (synthetic geometry, no PDFKit)

### T-020 — Geometry and line assembly
- **Status:** todo
- **Depends on:** T-004
- **Covers:** FR-04, FR-11
- **Files:** `Layout/PageGeometry.swift`, `Layout/LineAssembler.swift`
- **Do:** tech spec §5 (display space), §6.7.1.
- **Tests:** TC-U18, TC-U24.
- **Done when:** rotation cases and RTL ordering pass.

### T-021 — Reading order (XY-cut)
- **Status:** done
- **Depends on:** T-020
- **Covers:** FR-11
- **Files:** `Layout/ReadingOrder.swift`
- **Do:** tech spec §6.7.2.
- **Tests:** TC-U19.
- **Done when:** 2- and 3-column synthetic pages order correctly.

### T-022 — Font statistics, title and headings
- **Status:** done
- **Depends on:** T-020
- **Covers:** FR-06, FR-07
- **Files:** `Layout/FontStatistics.swift`, `Layout/HeadingClassifier.swift`
- **Do:** tech spec §6.7.3–4 (title incl. recurring-style rule, headings, levels, outline/TOC hints API).
- **Tests:** TC-U20.
- **Done when:** synthetic documents classify as specified.
  - *Spec gap filled during implementation:* the heading rules in §6.7.4(b) ("gap above ≥ 1.2 ×
    body spacing") and the heading-merge rule ("gap ≤ 1.3 × spacing") use numeric factors that
    were never added to the §10 constants table. Added `Constants.headingGapFactor` (1.2) and
    `Constants.headingMergeGapFactor` (1.3) and the matching §10 rows.
  - *Interpretation:* "numbering depth breaks ties" (§6.7.4) is read as: a heading whose text
    matches the numbered pattern uses its numbering depth as the level outright, overriding the
    sorted-distinct-size rank for that heading. This is the only reading under which numbering
    can actually *break* a tie — two headings sharing one rounded font size would otherwise
    always share one level under the pure size-rank rule.

### T-023 — TOC detection
- **Status:** done
- **Depends on:** T-022
- **Covers:** FR-08
- **Files:** `Layout/TOCDetector.swift`
- **Tests:** TC-U21.
- **Done when:** all TOC variants pass; non-TOC numeric pages are rejected.

### T-024 — Lists, preformatted and paragraphs
- **Status:** done
- **Depends on:** T-022
- **Covers:** FR-09, FR-10
- **Files:** `Layout/ListDetector.swift`, `Layout/ParagraphBuilder.swift`, `Layout/StructureAnalyzer.swift`
- **Do:** tech spec §6.7.4 lists, preformatted, paragraphs, cross-page continuation, page breaks; `StructureAnalyzer` orchestrates outline → TOC → title → headings → lists → preformatted → paragraphs.
- **Tests:** TC-U22, TC-U23.
- **Done when:** synthetic multi-page document yields the expected `[Block]`.
  - *Spec gap filled during implementation:* the preformatted rule's "gaps > 2 × size" and the
    list continuation's "± 3 pt" alignment were never named in the §10 constants table. Added
    `Constants.preformattedGapFactor` (2.0) and `Constants.listContinuationAlignmentTolerance`
    (3 pt), with matching §10 rows.
  - *Interpretation:* "the column's left edge" / "column width" (paragraph indent and short-line
    rules) are read as the minimum left edge and maximum line width observed across the whole
    body-line run passed to one `ParagraphBuilder.build` call — a run already corresponds to one
    body segment between headings/lists, i.e. one column in practice. A genuine multi-column
    body run concatenated without an intervening heading is out of scope for this reading.
  - *Interpretation:* the detected TOC block is placed immediately after the title (or at the
    very start, with none) rather than interleaved at its exact original line position — the
    realistic case, since a TOC occupies its own page(s); avoids a much more complex general
    interleaving scheme for a case that essentially never arises.
  - *Known limitation (documented, not fixed — spec's ordered-marker regex is intentionally
    simple):* `ListDetector` reads a single-letter initial + period ("A. Smith, Esq.") as an
    ordered list marker "A.". Locked in by a test rather than treated as a bug.
  - *Scope note:* `includePageBreaks` inserts `.pageBreak(page:)` only at paragraph-level page
    transitions (the dominant case). A page transition between two non-paragraph blocks (e.g.
    heading-to-heading across a page with no body text) does not get a page-break marker in this
    pass — `includePageBreaks` defaults to `false` and is not covered by TC-U22/TC-U23; flagged
    as a follow-up if full coverage is needed.

### T-025 — Repeated content filter
- **Status:** done
- **Depends on:** T-020
- **Covers:** FR-12, FR-16
- **Files:** `Sanitize/RepeatedContentFilter.swift`
- **Do:** sanitisation spec §5.
- **Tests:** TC-U17.
- **Done when:** Rules A/B/C and the "Chapter N" guard pass.

## Phase 3 — PDF extraction (PDFKit, CoreGraphics, Vision)

### T-030 — DocumentOpener and SourceInventory
- **Status:** done
- **Depends on:** T-004
- **Covers:** FR-02, FR-03, FR-17, FR-19, NFR-06
- **Files:** `Ingest/DocumentOpener.swift`, `Ingest/SourceInventoryBuilder.swift`, `Ingest/MetadataValues.swift` (transient values for the verifier)
- **Do:** tech spec §6.1. Owner-password path via `permissionsStatus == .owner`.
- **Tests:** TC-U29; fixture cases `not-a-pdf`, `truncated`, `encrypted-*`, `copy-restricted*` enabled in TC-F01.
- **Done when:** those fixture cases pass.
  - *Scope note:* `DocumentOpener`/`SourceInventoryBuilder`/`MetadataValues` are implemented and
    covered directly against the real fixture PDFs (`DocumentOpenerTests`,
    `SourceInventoryBuilderTests` — all password/copy/header/inventory paths pass). The literal
    "enabled in TC-F01" wiring (replacing `FixtureSuiteTests`'s "pipeline pending" stub) happens
    at T-035, once `ExtractionPipeline` exists to run fixtures through end to end.

### T-031 — Glyph extraction and word building
- **Status:** done
- **Depends on:** T-030, T-020
- **Covers:** FR-04, FR-14
- **Files:** `Extraction/GlyphExtractor.swift`, `Extraction/WordBuilder.swift`
- **Do:** tech spec §6.2 and §6.4 (UTF-16 offsets, surrogate pairs, zero-width glyphs stay in words, keep both `box` (display space) and `pageBox` (page space), fallback via `selectionsByLine`).
- **Tests:** TC-U14 plus a fixture-backed test: `simple-structured` page 1 words include "infra-" and "structure".
- **Done when:** tests pass.
  - *Spec drift found during implementation:* two real `PDFKit` behaviors contradicted the
    spec's literal reading (both now in CLAUDE.md's Gotchas so they aren't rediscovered): (1)
    whitespace must be a separator unconditionally — gating it on an empty box (as a literal
    reading of §6.2 suggested) swallowed every ordinary space into the surrounding word, since
    PDFKit gives most spaces a real, non-empty advance box; (2) "empty box" for the
    zero-width/format-character rule must mean zero *width* (`box.width <= 0`), not
    `CGRect.isEmpty` — PDFKit occasionally reports a zero-*height* box for an ordinary, fully
    visible glyph, and `isEmpty` also matches that, excluding a real character from gap
    measurements. (3) *Implementation workaround, not a rule change:* `characterBounds(at:)` can
    report the wrong line's Y for the last few characters before a line boundary (confirmed via
    the `simple-structured` fixture's "infra-"/"structure" hyphenation, which first came out as
    "in"/"fra-structure"); `GlyphExtractor` now cross-references `selectionsByLine()` — which
    does not have this bug — to correct each glyph's vertical extent, keeping
    `characterBounds`'s (reliable) horizontal measurement.

### T-032 — Glyph-level filters
- **Status:** done
- **Depends on:** T-031
- **Covers:** FR-13
- **Files:** `Sanitize/GlyphFilter.swift`
- **Do:** sanitisation spec §2.
- **Tests:** TC-U13; on `hidden-content` the run "CANARY-ROTATED" is removed as one run per page.
- **Done when:** tests pass.
  - *Spec gap filled during implementation:* the CJK/Hangul/Kana vertical-writing exception's
    "≥ 80%" was never added to the §10 constants table. Added `Constants.cjkVerticalExceptionRatio`
    (0.8) with a matching §10 row.
  - *Spec drift found during implementation (GlyphExtractor, T-031):* the real `CANARY-ROTATED`
    watermark (`c.rotate(45)` + `drawString`, sanitisation spec's own example) was not detected
    at first — `characterBounds(at:)` is unreliable across a rotated-CTM run (see CLAUDE.md's
    Gotchas). Fixed by detecting a `selectionsByLine()` line that "looks rotated" (tall relative
    to its width and length) and synthesizing evenly spaced diagonal boxes for its characters
    instead of trusting `characterBounds`. Confirmed removed on both pages of `hidden-content`.

### T-033 — Visibility filter and overlap dedupe
- **Status:** todo
- **Depends on:** T-032
- **Covers:** FR-13
- **Files:** `Extraction/PageRasterizer.swift`, `Sanitize/VisibilityFilter.swift`, `Sanitize/OverlapDeduper.swift`
- **Do:** sanitisation spec §3–4 with the exact constants of `scripts/reference/visibility_reference.py`. Keep the ink computation a pure function over a `GrayRaster` value type so it is unit-testable.
- **Tests:** TC-U15, TC-U16; `hidden-content` removes every non-repeated canary word and keeps "Inline check: alpha omega closes the line."; `scanned-with-ocr-layer` keeps all words; `reportExactly` guards on clean fixtures.
- **Done when:** verdicts match the reference on all fixtures.

### T-034 — OCR recogniser
- **Status:** todo
- **Depends on:** T-033
- **Covers:** FR-05
- **Files:** `Extraction/OCRRecognizer.swift`
- **Do:** tech spec §6.5 (trigger rule, 300 dpi render, Vision request, conversion, confidence warning, cancellation).
- **Tests:** TC-U28; fixture `scanned` (ocrTolerant) and `scanned-with-ocr-layer` (no OCR).
- **Done when:** both fixture cases pass on macOS and iOS simulator.

### T-035 — ExtractionPipeline actor
- **Status:** todo
- **Depends on:** T-010, T-011, T-012, T-024, T-025, T-033, T-034
- **Covers:** FR-04, FR-23, NFR-03, NFR-09, FR-19
- **Files:** `Pipeline/ExtractionPipeline.swift`, `Pipeline/ProgressReporter.swift`
- **Do:** tech spec §1, §6 order (word-level sanitising §6.4b happens *before* repeated-content and outline/TOC matching — fixture canary CANARY-ZWVARIANT enforces it), §7 concurrency/cancellation, progress stages and fractions (opening 2 %, pages 80 % split per page, layout 10 %, cleaning 8 %), language detection with `NLLanguageRecognizer`.
- **Tests:** TC-F01 (all cases enabled), TC-F02, TC-F03, TC-F04, TC-F05, TC-F06.
- **Done when:** the full fixture suite is green.

## Phase 4 — CLI

### T-040 — `pdfclean` command-line tool
- **Status:** todo
- **Depends on:** T-035, T-013, T-014
- **Covers:** FR-24
- **Files:** `Sources/pdfclean/main.swift`, `scripts/e2e.sh`
- **Do:** FR-24 arguments and exit codes (no third-party argument parser; small hand-written parser), `--report` writes the `SanitizationReport` as JSON (no metadata values). `e2e.sh` runs every manifest case through the CLI and checks exit codes and `mustNotContain`.
- **Tests:** TC-E01.
- **Done when:** `make e2e` is green.

## Phase 5 — App

### T-050 — AppModel state machine and JobWorkspace
- **Status:** todo
- **Depends on:** T-035
- **Covers:** FR-01, FR-02, FR-03, FR-23, NFR-02
- **Files:** `App/Shared/AppModel.swift`, `App/Shared/JobWorkspace.swift`, `App/Shared/UserFacingError.swift`
- **Do:** tech spec §9.1 and §9.3 (temp copy, cleanup, launch purge), error mapping §8.
- **Tests:** TC-U30 (JobWorkspace lives in the package as `Pipeline/JobWorkspace.swift` so it is testable) and AppModel state-transition tests with a fake pipeline protocol.
- **Done when:** all transitions in the diagram are covered by tests.

### T-051 — Import screen
- **Status:** todo
- **Depends on:** T-050
- **Covers:** FR-01, NFR-05
- **Files:** `App/Shared/Views/ImportView.swift`, `RootView.swift`
- **Do:** UI spec §1; `.fileImporter`, `.dropDestination`, non-PDF banner, ⌘O.
- **Done when:** manual check on macOS + iPhone + iPad simulators.

### T-052 — Password sheet
- **Status:** todo
- **Depends on:** T-051
- **Covers:** FR-02, FR-03
- **Files:** `App/Shared/Views/PasswordSheet.swift`
- **Do:** UI spec §2 (user vs owner variants).
- **Done when:** manual steps 2–3 of the QA checklist pass.

### T-053 — Processing screen
- **Status:** todo
- **Depends on:** T-051
- **Covers:** FR-23, NFR-05
- **Files:** `App/Shared/Views/ProcessingView.swift`
- **Do:** UI spec §3 with Esc/Cancel.
- **Done when:** manual step 4 passes.

### T-054 — Result screen: outline and preview
- **Status:** todo
- **Depends on:** T-053
- **Covers:** FR-20
- **Files:** `App/Shared/Views/ResultView.swift`, `OutlineSidebar.swift`, `PreviewView.swift`, `BlockView.swift`
- **Do:** UI spec §4 (split view, scroll-to, Show source).
- **Done when:** manual step 1 passes; TC-UI01 if implemented.

### T-055 — Report panel and identifier redaction
- **Status:** todo
- **Depends on:** T-054
- **Covers:** FR-18, FR-19
- **Files:** `App/Shared/Views/ReportPanel.swift`, `IdentifierList.swift`
- **Do:** UI spec §4 Cleaned panel; tooltips; Redact all.
- **Done when:** manual step 5 (report part) passes.

### T-056 — Export
- **Status:** todo
- **Depends on:** T-054, T-014
- **Covers:** FR-21, FR-22
- **Files:** `App/Shared/CleanTextDocument.swift`, toolbar in `ResultView.swift`
- **Do:** tech spec §9.3 export; format picker; ⌘S; post-export xattr strip on macOS; verification failure alert.
- **Done when:** manual steps 5–6 pass.

### T-057 — Options
- **Status:** todo
- **Depends on:** T-050
- **Covers:** FR-05, FR-12, FR-15, FR-16
- **Files:** `App/Shared/Views/OptionsView.swift`, `App/Shared/OptionsStore.swift`
- **Do:** UI spec §5; `@AppStorage` for settings only; macOS `Settings` scene, iOS sheet.
- **Done when:** toggling each option changes the next extraction (checked with `hidden-content`).

### T-058 — iOS/iPadOS adaptations
- **Status:** todo
- **Depends on:** T-054, T-055, T-056
- **Covers:** NFR-04, FR-01
- **Do:** compact layout (sheets for outline/report), iPad split view, Files save flow, Dynamic Type.
- **Done when:** manual step 8 passes on iPhone and iPad simulators.

### T-059 — Localisation (German) and accessibility pass
- **Status:** todo
- **Depends on:** T-051, T-052, T-053, T-054, T-055, T-057
- **Covers:** NFR-08, NFR-05
- **Files:** `App/Resources/Localizable.xcstrings`
- **Tests:** TC-U25, TC-U26.
- **Done when:** both pass; VoiceOver walk-through done.

## Phase 6 — Hardening and release

### T-060 — Robustness fuzzing
- **Status:** todo
- **Depends on:** T-035
- **Covers:** NFR-06
- **Tests:** TC-U27.
- **Done when:** 200 seeded mutations never crash.

### T-061 — Performance and memory
- **Status:** todo
- **Depends on:** T-035
- **Covers:** NFR-03
- **Do:** profile with Instruments (Time Profiler, Allocations) on `perf-200-pages` and a generated 500-page file; fix hotspots (e.g. raster reuse, masked pixel loops over `UnsafeBufferPointer`).
- **Tests:** TC-F04, TC-M04.
- **Done when:** budgets in NFR-03 met in Release.

### T-062 — Coverage gate
- **Status:** todo
- **Depends on:** T-035
- **Covers:** NFR-07
- **Do:** `make coverage` using `swift test --enable-code-coverage` + `llvm-cov report`; fail below 80 %.
- **Tests:** TC-Q01.

### T-063 — Offline proof and privacy review
- **Status:** todo
- **Depends on:** T-056
- **Covers:** NFR-01, NFR-02
- **Do:** TC-M03; review logs in Console.app during a full run; confirm temp folder empty after quit; run the `sanitization-auditor` agent.
- **Tests:** TC-M03.

### T-064 — Log hygiene test
- **Status:** todo
- **Depends on:** T-002
- **Covers:** NFR-02
- **Tests:** TC-E03 runs in `make verify`.

### T-065 — README and user guide
- **Status:** todo
- **Depends on:** T-058
- **Covers:** FR-01, FR-21
- **Do:** update README (install, build, usage, limitations); in-app "About" text explaining what is removed.

### T-066 — XCUITest smoke (optional)
- **Status:** todo
- **Depends on:** T-054
- **Covers:** FR-20
- **Do:** add `PDFCleanUITests` target to `project.yml`; launch argument `-uiTestOpen <path>` handled by `AppModel` in DEBUG only.
- **Tests:** TC-UI01, TC-U26.

## Backlog (not scheduled for v1)

### T-090 — DOCX export (backlog)
- **Status:** todo
- **Depends on:** T-013
- **Covers:** FR-21
- **Do:** minimal OOXML writer (document.xml + styles, *no* docProps/core.xml or app.xml), zip via a tiny stored-zip writer (no third-party). Confirm demand first (requirements Q2).

### T-091 — Clean PDF export (backlog)
- **Status:** todo
- **Depends on:** T-013
- **Covers:** FR-21
- **Do:** investigate generating a PDF without Info/XMP/ID; CoreGraphics adds Producer/CreationDate, so this needs a custom writer — evaluate effort.

### T-092 — OCR cross-check of text layers over images (backlog)
- **Status:** todo
- **Depends on:** T-034
- **Covers:** FR-13
- **Do:** sanitisation spec §8.

### T-093 — Vision document recognition on macOS 26 / iOS 26 (backlog)
- **Status:** todo
- **Depends on:** T-034
- **Covers:** FR-05
- **Do:** tech spec §6.5 optional enhancement behind `#available`.
