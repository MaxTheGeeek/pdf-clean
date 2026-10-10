# 01 · Requirements

**Product:** PDFClean — an offline macOS and iOS/iPadOS app that turns a PDF into a
clean, structured text document (title, headings, table of contents, paragraphs,
lists) with every hidden token, identifier and piece of metadata removed, so the
result can be shared with AI tools or anyone else safely.

**Primary flow:** Open PDF → wait for extraction → review structured result → save
(Markdown, HTML or plain text).

## 1. Context and problem

Users receive PDFs that carry content they cannot see: per-recipient watermarks,
white or invisible text, zero-width / Unicode-tag characters ("ASCII smuggling"),
metadata and XMP identifiers, annotations and attachments. Some of these exist to
trace or block a document when it is uploaded to an AI service, others inject
instructions into AI tools. The user needs the *visible* content only, with its
structure preserved, produced entirely on their own device.

## 2. Users and stories

| ID | As a… | I want to… | so that… |
|----|-------|-----------|----------|
| US-1 | knowledge worker on a Mac | drop a PDF on the window and get clean Markdown | I can paste/upload it into an AI tool without hidden content |
| US-2 | user on iPhone/iPad | pick a PDF from Files and save the clean result back to Files | I can do the same on the go |
| US-3 | cautious user | see exactly what was removed | I trust the result |
| US-4 | user with a scanned PDF | still get the text | scans are not a dead end |
| US-5 | user with a password-protected PDF | enter the password and continue | protected documents I own still work |
| US-6 | developer (us) | run the pipeline from the command line on fixtures | the behaviour is testable end to end without UI |

## 3. Functional requirements

Each requirement has acceptance criteria (AC). Fixture IDs refer to
`Packages/PDFCleanKit/Tests/PDFCleanKitTests/Fixtures/manifest.json`.

### FR-01 — Import a PDF
- macOS: "Open…" button, File ▸ Open (⌘O) and drag & drop of one `.pdf` onto the window.
- iOS/iPadOS: "Choose PDF" button using the system document picker (Files, iCloud Drive, on-device providers); drag & drop on iPad.
- Only one document at a time. Accepted type: `UTType.pdf`.
- AC1: Given the import screen, when the user selects a PDF, processing starts within 0.5 s.
- AC2: Dropping a non-PDF file shows "This file is not a PDF." and stays on the import screen.

### FR-02 — Validate and unlock
- Reject files that are not PDFs (no `%PDF-` header within the first 1024 bytes) → `notAPDF`.
- Reject unreadable/corrupt PDFs without crashing → `unreadablePDF`.
- Encrypted PDFs: prompt for the password; wrong password → message and re-prompt; Cancel returns to import.
- AC1: `encrypted-ok` with password `open-sesame` extracts the expected text.
- AC2: `encrypted-missing-password` → `passwordRequired`; `encrypted-wrong-password` → `wrongPassword`.
- AC3: `not-a-pdf` → `notAPDF`. `truncated` → no crash (success or `unreadablePDF`).

### FR-03 — Respect copy permission
- If the document does not allow copying, extraction is refused with `copyingNotPermitted` and the UI offers an owner-password prompt. If unlocking with the owner password lifts the restriction, processing continues.
- AC1: `copy-restricted` → `copyingNotPermitted`; with owner password `owner-only` it extracts.

### FR-04 — Extract text in reading order
- Text-based pages are extracted with PDFKit using character geometry, rebuilt into words and lines in visual reading order (top-to-bottom, left-to-right; right-to-left lines for RTL scripts).
- AC1: `simple-structured`, `scanned-with-ocr-layer` and `encrypted-ok` produce all `mustContain` phrases.

### FR-05 — OCR fallback for scanned pages (on device)
- A page whose text layer yields no visible words but has visible ink is recognised with Vision (`VNRecognizeTextRequest`, accurate, language correction on). Languages default to English and German; automatic language detection on.
- OCR mode option: Auto (default) / Off / Always.
- AC1: `scanned` → `ocrPages == [1]` and its `mustContain` phrases match (OCR-tolerant comparison).
- AC2: `scanned-with-ocr-layer` → `ocrPages == []` (its invisible text layer is used, not OCR).

### FR-06 — Detect the document title
- The title is the largest text in the upper half of the first non-empty page when its size ≥ 1.4 × body size; consecutive lines with the same style merge. Metadata titles are **never** used.
- AC1: titles of `simple-structured`, `toc`, `hidden-content`, `two-column`, `unicode-normalization` match the manifest.

### FR-07 — Detect headings and levels
- Headings are found from (in priority order) the PDF outline, the detected table of contents, then typography (size, weight, numbering, isolation). Levels 1–4.
- AC1: `simple-structured` and `toc` heading lists (level + text) equal the manifest exactly.
- AC2: `perf-200-pages` has exactly 200 headings.

### FR-08 — Detect a table of contents
- TOC pages are recognised by a "Contents"-type heading (EN/DE/FR/ES/IT/FA keywords) or by a high ratio of `title … page-number` lines. Entries keep title, level and the printed page number; dot leaders are removed.
- AC1: `toc` → `tocEntries` equal the manifest; no dot-leader sequences in the output.

### FR-09 — Rebuild paragraphs
- Lines join into paragraphs; hyphenated line breaks are repaired; a paragraph interrupted by a page break (and running headers/footers) continues on the next page; new paragraphs start on larger vertical gaps, indentation, or a short line ending a sentence.
- AC1: `simple-structured` `mustContain`/`mustContainAfterFiltering` phrases match and `separateParagraphs` pairs are in different blocks; `mustNotContainDerived` never appears.

### FR-10 — Detect lists
- Bulleted (•, ◦, ▪, -, *, – …) and ordered (1., 1), a., i.) items, with wrapped continuation lines merged into the item and nesting by indentation.
- AC1: `simple-structured` `listItems` equal the manifest (order, ordered flag, text).

### FR-11 — Multi-column reading order
- Columns are detected per page (whitespace gutters); full-width blocks act as separators; each column is read completely before the next.
- AC1: `two-column` `orderedPhrases` appear in order (the source writes the right column first).

### FR-12 — Remove running headers, footers and page numbers
- Small-font lines in the top/bottom page margins repeating on ≥ 50 % of pages (digits normalised) and isolated page-number lines in the margins are removed (option, default on).
- AC1: `simple-structured` output contains none of `mustNotContain`; `reportAtLeast.removedHeaderFooterLines` met.
- AC2: no heading of `perf-200-pages` is removed by this rule.

### FR-13 — Remove hidden text
- Words are removed when they are: not visibly rendered (invisible render mode, same colour as background, covered by an opaque shape, clipped), off the crop box, smaller than 2 pt, or part of rotated runs (> 10° baseline angle, default on). Duplicate overlapping words (fake bold) are collapsed.
- Legitimate invisible OCR layers over scanned images are kept (ink exists under them).
- AC1: `hidden-content` output contains no `mustNotContain` string and no `mustNotContainDerived` string; all `mustContain` phrases are present; `occurrences` match; `reportAtLeast` met.
- AC2: `scanned-with-ocr-layer` keeps its text.
- AC3: verdicts agree with `scripts/reference/visibility_reference.py --check` on all fixtures.

### FR-14 — Remove invisible and steganographic Unicode
- Zero-width characters, word joiners, BOM, bidi controls, Unicode TAG characters, variation-selector supplements, private-use characters, unassigned code points, C0/C1 controls and soft hyphens are removed (context-aware exceptions for ZWNJ/ZWJ in scripts that need them and emoji sequences). Ligatures are decomposed; text is NFC-normalised.
- AC1: none of `mustNotContainCodepoints` appear in any exported format for `hidden-content` and `unicode-normalization`.
- AC2: umlauts, ß, accents and curly apostrophes in `unicode-normalization` are preserved.

### FR-15 — Normalise homoglyphs and whitespace
- Mixed-script words whose non-Latin letters are Latin look-alikes (Cyrillic/Greek) are converted to Latin; fullwidth and mathematical-alphanumeric letters map to ASCII; all space separators become U+0020 and runs collapse (option "Normalise look-alike characters", default on). Pure Cyrillic/Greek words are untouched.
- AC1: `hidden-content` contains "The password policy applies to all staff." and "Spacing test with odd whitespace."

### FR-16 — Remove repeated watermark and fingerprint lines
- Identical text at the same position on ≥ 50 % of pages (≥ 2 pages) is removed (option, default on). Rotated watermark text is removed by FR-13.
- AC1: `hidden-content` contains neither `max@example.com` nor `7F3A-99X2` nor `Copy #00417`.

### FR-17 — Never carry source metadata or non-content objects
- Output is generated solely from the document model. Info dictionary, XMP, trailer ID, outline targets, annotations (comments, links), form fields, attachments and JavaScript never appear. Their presence is reported (names and counts only) in the source inventory.
- AC1: `hidden-content` — every `CANARY-META-*`, `CANARY-XMP-*`, `CANARY-ANNOT-*`, `CANARY-LINK`, `CANARY-FORM-VALUE`, `CANARY-ATTACH-PAYLOAD` is absent; `sourceInventory` matches the manifest.

### FR-18 — Flag suspicious identifiers in visible text
- Visible strings that look like identifiers (UUIDs, long hex, base64/JWT tokens, e-mail addresses, licence-key patterns) are listed with occurrence counts. The user can redact any or all of them (replaced by `[REDACTED]`). Default: listed, not redacted.
- AC1: `hidden-content` lists `3f2a9c1e-77b4-4c2e-9d1a-0b6e5f4a3c21`; redacting it removes it from all formats.

### FR-19 — Sanitisation report
- After extraction the user sees counts per category (hidden words, tiny glyphs, off-page, rotated, duplicates, repeated lines, headers/footers, invisible code points, homoglyphs, whitespace, ligatures), OCR pages, warnings and the source inventory (metadata *keys*, XMP present, annotations, form fields, attachments, outline, encryption). Metadata *values* are not displayed.
- The report is never embedded in exported files.
- AC1: `hidden-content` report satisfies `reportAtLeast` and `sourceInventory`.

### FR-20 — Structured preview
- The result screen shows the document structure (outline of title/headings) and a formatted preview; selecting an outline item scrolls the preview. A "Source" toggle shows the exact text of the selected export format.
- AC1: UI test — after processing `simple-structured`, the outline shows 6 entries (title + 5 headings).

### FR-21 — Export clean files
- Formats: Markdown (`.md`, default), HTML (`.html`, self-contained, print-friendly) and plain text (`.txt`). UTF-8 without BOM, LF line endings, final newline.
- Suggested file name: `<original-stem>-clean.<ext>` (stem sanitised to `[A-Za-z0-9 ._-]`); option "Neutral file name" → `document-clean.<ext>`.
- Files contain no generator tags, timestamps, comments or metadata. On macOS, extended attributes are stripped after writing (best effort).
- AC1: exported files for every success fixture start with document content (Markdown `# ` or text) or `<!doctype html>`; HTML contains only `charset`/`viewport` meta tags.
- AC2: exporting the same document twice yields byte-identical files.

### FR-22 — Output verification
- Every exported string is checked by `OutputVerifier` for forbidden code points and source-metadata values. Violations block the export with an internal-error message.
- AC1: unit tests feed forbidden strings to the verifier and get violations; all fixture exports pass.

### FR-23 — Progress and cancel
- Processing shows the current stage (Opening, Reading pages, Checking visibility, Recognising text (OCR), Analysing layout, Cleaning, Done) and page X of N; Cancel stops within 1 s and returns to import, deleting temporary files.
- AC1: cancelling `perf-200-pages` at 50 % returns to idle within 1 s.

### FR-24 — Command-line tool (developer)
- `pdfclean <input.pdf> [-o out] [--format md|html|txt] [--password P] [--report report.json] [--no-ocr] [--keep-headers] [--keep-watermarks] [--no-homoglyphs] [--redact-identifiers]` (macOS only, not shipped in the app).
- Exit codes: 0 success, 2 usage, 3 password required/wrong, 4 copying not permitted, 5 not a PDF/unreadable, 6 verification failed, 1 other.
- AC1: running the CLI over every fixture reproduces the manifest expectations (used by `make e2e`).

## 4. Non-functional requirements

### NFR-01 — Offline
- No network APIs in any target; macOS sandbox without network entitlements; `make check-offline` passes. Verified by script and by running with networking disabled.

### NFR-02 — Privacy
- No document data persisted between launches; temporary files removed (job end, cancel, next launch); logs contain no document content, names or metadata values (`os.Logger` with counts only).

### NFR-03 — Performance (Apple silicon, Release build)
- Text-based PDFs: ≤ 0.1 s/page median; `perf-200-pages` ≤ 20 s end to end (Debug test tolerance × 3).
- OCR pages: ≤ 2.5 s/page.
- Peak memory ≤ 600 MB for a 500-page text PDF (pages processed sequentially; rasters released per page).
- UI remains responsive (main thread never blocked > 100 ms).

### NFR-04 — Platforms
- macOS 14 Sonoma or later; iOS/iPadOS 17 or later; Apple silicon and Intel Macs. Built with Xcode 16+ (Swift 6 toolchain).

### NFR-05 — Accessibility
- VoiceOver labels on all controls, Dynamic Type on iOS, full keyboard operation on macOS, sufficient contrast in light and dark mode.

### NFR-06 — Robustness
- Never crash on malformed input; all failures map to `PipelineError`. Limits: ≤ 2,000 pages and ≤ 500 MB per file (clear message when exceeded). Warning above 300 pages.

### NFR-07 — Maintainability
- Core logic in Swift package `PDFCleanKit` with ≥ 80 % line coverage; app target contains only UI and glue. Swift 6 language mode, strict concurrency. Every heuristic constant is named and documented.

### NFR-08 — Localisation
- UI strings in a String Catalog; English required, German provided (Austrian/German users). Extraction works for any Latin, Cyrillic, Greek, Arabic-script and CJK text that PDFKit can read.

### NFR-09 — Determinism
- Same input + options ⇒ byte-identical outputs on the same OS version.

## 5. Out of scope (v1)

- Reconstructing tables as real tables (table-like regions are kept as preformatted text), images/figures, footnote linking, mathematical formulae.
- DOCX/PDF export (backlog T-090/T-091), editing the text in-app, batch processing in the UI, Windows/Android/Linux.
- Removing visible content other than repeated lines/headers/footers (users redact identifiers explicitly).
- Detecting hidden text in OCR text layers that sits over real ink (see sanitisation spec §8, backlog T-092).

## 6. Assumptions and open questions

- A1: "Download" means saving through the system save dialog (macOS) / Files (iOS).
- A2: Users own or are authorised to process the documents; the app honours PDF permissions (P3).
- Q1: Should identifier redaction default to on? Current answer: off, list prominently. Revisit after user testing.
- Q2: DOCX output requested by business users? Backlog until confirmed.
