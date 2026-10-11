# 05 · Test plan

## 1. Strategy

| Level | Tool | Where | Runs in |
|-------|------|-------|---------|
| Unit (pure functions, synthetic inputs) | Swift Testing | `Tests/PDFCleanKitTests/Unit/` | `make test` (seconds) |
| Fixture integration (real PDFs through the whole pipeline) | Swift Testing, parameterised over `manifest.json` | `Tests/PDFCleanKitTests/Fixtures/` | `make test` |
| CLI end-to-end | `pdfclean` + `scripts/e2e.sh` | repo | `make e2e` (macOS) |
| Static checks | `scripts/check_offline.sh`, `scripts/check_specs.py`, `swift format lint` | repo | `make verify` |
| Fixture validity | `scripts/fixtures/verify_fixtures.py` + `scripts/reference/visibility_reference.py --check` | repo | `make fixtures-verify` |
| UI | XCUITest smoke (optional) + manual checklist | `App/UITests`, §5 | before release |

Offline proof: `make check-offline` must pass with networking disabled; the manual QA checklist must still verify that the app never opens the network and that output generation remains fully offline-safe.

Rules
- Every FR/NFR has at least one test case below (enforced by `make check-specs`).
- Tests never touch the network and never write outside the test's temporary directory.
- A bug fix starts with a failing test (unit or new fixture).
- Fixtures are regenerated only via `make fixtures`; their expectations live in
  `scripts/fixtures/build_manifest.py` → `manifest.json`. Hand-editing `manifest.json`
  is not allowed.

## 2. Fixture harness (TC-F01) — how `manifest.json` is evaluated

Load the manifest with `Bundle.module`; one parameterised `@Test(arguments:)` case per
fixture `id`. For each case run `ExtractionPipeline` with default options and
`password`, then render all three formats.

| Manifest field | Assertion |
|----------------|-----------|
| `expectError` | the stream throws `PipelineError` whose case name equals the value |
| `expectNoCrash` | completes or throws any `PipelineError` — never traps |
| `title` | the `.title` block text equals the value |
| `headings` | `.heading` blocks `[level, text]` in order equal the value |
| `headingCount` | number of `.heading` blocks |
| `tocEntries` | entries of the `.tableOfContents` block `[level, title, page]` |
| `listItems` | `.listItem` blocks `(ordered, text)` in order |
| `mustContain`, `mustContainAfterFiltering` | each phrase is a substring of the **plain-text** export after collapsing whitespace (no Markdown escaping involved) |
| `ocrTolerant` | for this fixture compare `mustContain`/`title` on lower-cased alphanumerics only |
| `mustNotContain`, `mustNotContainDerived` | not a substring of **any** of the three exports |
| `mustNotContainCodepoints` | none of the code points occur in any export |
| `occurrences` | exact substring count in the plain-text export |
| `orderedPhrases` | first occurrences appear in increasing offset order |
| `separateParagraphs` | phrase a and b are found in different `.paragraph` blocks |
| `ocrPages` | `report.ocrPages` equals the value exactly |
| `reportAtLeast` / `reportExactly` | counters by name (`KeyPath` table) ≥ / == value |
| `sourceInventory` | `hasXMP`, `hasOutline`, `hasFormFields`, `embeddedFileCount` equal; `annotationCount ≥ minAnnotationCount`; `metadataKeys ⊇ metadataKeysInclude` |
| `suspiciousIdentifiers` | each value is the text of a finding |
| `maxSeconds` | wall time ≤ value (× 3 in Debug builds) |

## 3. Test cases

| ID | Test | Level | Covers |
|----|------|-------|--------|
| TC-U01 | `UnicodeSanitizer` removes every code point of sanitisation §6 step 3 (table-driven, one case per range edge) and counts them | Unit | FR-14 |
| TC-U02 | ZWNJ/ZWJ context rules: Persian "می⟨U+200C⟩خواهم" keeps ZWNJ, Hindi conjunct keeps ZWJ, emoji ZWJ sequence kept, Latin "a⟨U+200C⟩b" loses it | Unit | FR-14 |
| TC-U03 | Ligatures decomposed, PUA bullets → •, NFC applied, umlauts/ß/accents unchanged, ² ½ ™ unchanged | Unit | FR-14 |
| TC-U04 | Whitespace: all Zs → space, runs collapsed, tabs only kept in preformatted, counter correct | Unit | FR-15 |
| TC-U05 | Homoglyphs: "pаssword" → "password"; "Москва" and "Αθήνα" untouched; fullwidth "ＡＢＣ" → "ABC"; math bold "𝐀" → "A" | Unit | FR-15 |
| TC-U06 | `IdentifierDetector` positives (uuid, jwt, hex, base64Token, email, keyPattern) and negatives (dates, ISBN-like words, "2026-10-10", plain words, "COVID-19") | Unit | FR-18 |
| TC-U07 | Redaction replaces exact matches in every block type and all formats; model unchanged | Unit | FR-18, FR-21 |
| TC-U08 | Markdown renderer golden test on a synthetic document with every block type, escaping cases (`*`, `_`, `#` at line start, `1.` at line start) | Unit | FR-21 |
| TC-U09 | HTML renderer: skeleton exactly as spec, escaping, only charset/viewport meta, no script/link/img tags, `lang` from dominant language | Unit | FR-21, FR-17 |
| TC-U10 | Plain-text renderer golden test | Unit | FR-21 |
| TC-U11 | `OutputVerifier` flags forbidden code points, non-ASCII spaces, C0 controls, metadata values; passes clean text and allowed ZWNJ contexts | Unit | FR-22 |
| TC-U12 | Suggested file names: sanitised stem, neutral option, extension per format, empty/emoji-only stems → "document" | Unit | FR-21 |
| TC-U13 | `GlyphFilter`: off-page (< 50 % inside), tiny (< 2 pt), rotated runs (≥ 3 diagonal glyphs), vertical CJK exception, option off keeps rotated | Unit | FR-13 |
| TC-U14 | `WordBuilder`: zero-width glyph stays inside the word, surrogate pair = 1 glyph, gap split at 0.25 × size, newline split | Unit | FR-04, FR-14 |
| TC-U15 | `VisibilityFilter` on synthetic rasters: black ink visible, white region hidden, neighbour descenders masked (tight case), fully overlapped → full-box fallback, dark background with light text visible | Unit | FR-13 |
| TC-U16 | `OverlapDeduper`: IoU ≥ 0.7 same text removed once; different text or IoU < 0.7 kept | Unit | FR-13 |
| TC-U17 | `RepeatedContentFilter`: Rule A digits normalised, size cap protects "Chapter N" headings, Rule B exact text + position, Rule C page-number patterns (EN/DE/roman), single-page no-op | Unit | FR-12, FR-16 |
| TC-U18 | `LineAssembler`: clustering by vertical overlap, split at gutters (2 × size), RTL line ordering | Unit | FR-04, FR-11 |
| TC-U19 | `ReadingOrder` XY-cut: title + 2 columns + full-width footer block ordering; 3 columns; no false split on justified text | Unit | FR-11 |
| TC-U20 | Title and heading classifier on synthetic lines: size levels, bold-at-body level, numbering tie-break, multi-line merge, recurring style is not a title | Unit | FR-06, FR-07 |
| TC-U21 | TOC detector: dot leaders, spaces leaders, roman page numbers, wrapped entries, "Inhaltsverzeichnis", continuation page, non-TOC page with numbers is not TOC | Unit | FR-08 |
| TC-U22 | List detector: bullets set, ordered markers, continuation alignment ± 3 pt, nesting levels, "A. Smith" style false positive documented | Unit | FR-10 |
| TC-U23 | Paragraph builder: gap rule, indent rule, short-line rule, hyphen join (lowercase/uppercase/digit), soft hyphen join, cross-page continuation | Unit | FR-09 |
| TC-U24 | `PageGeometry`: page space ↔ display space for crop-box offsets and /Rotate 0/90/180/270 | Unit | FR-04 |
| TC-U28 | OCR observation → `Line` conversion (normalised bottom-left → display space, size estimate) | Unit | FR-05 |
| TC-U29 | `SourceInventory` builder on fixtures: keys only, values absent from the report's encoded JSON | Unit | FR-17, FR-19 |
| TC-U30 | `JobWorkspace`: copies input to temp, deletes on finish/cancel, purges leftovers at launch | Unit | NFR-02 |
| TC-F01 | Fixture manifest suite (§2) for all 15 cases | Fixture | FR-02, FR-03, FR-04, FR-05, FR-06, FR-07, FR-08, FR-09, FR-10, FR-11, FR-12, FR-13, FR-14, FR-15, FR-16, FR-17, FR-18, FR-19, NFR-06 |
| TC-F02 | Determinism: two runs of every success fixture → byte-identical exports in all formats | Fixture | NFR-09, FR-21 |
| TC-F03 | Every success fixture export passes `OutputVerifier` in all formats | Fixture | FR-22, FR-17 |
| TC-F04 | Performance: `perf-200-pages` within `maxSeconds` (× 3 Debug) | Fixture | NFR-03 |
| TC-F05 | Cancellation: cancel `perf-200-pages` after first progress ≥ 0.5 → `cancelled` within 1 s, temp files gone | Fixture | FR-23, NFR-02 |
| TC-F06 | Progress events: stages in spec order, `fractionCompleted` monotonic, ends with `.finished` | Fixture | FR-23 |
| TC-E01 | `scripts/e2e.sh`: CLI over every fixture; exit codes per FR-24; outputs satisfy the manifest checks reused via `pdfclean --report` JSON | E2E | FR-24 |
| TC-E02 | `scripts/check_offline.sh` passes (no network APIs, no network entitlements) | Static | NFR-01 |
| TC-E03 | Log hygiene: `check_offline.sh` rejects any logging API other than `Log.event` (StaticString keys, Int values) | Static | NFR-02 |
| TC-M01 | Manual macOS checklist (§5) | Manual | FR-01, FR-20, FR-21, FR-23, NFR-05 |
| TC-M02 | Manual iPhone + iPad simulator checklist (§5) | Manual | FR-01, NFR-04 |

## 4. Fixture inventory

| File | Purpose |
|------|---------|
| simple-structured.pdf | title, 2 heading levels, hyphenation, lists, header/footer, cross-page paragraph |
| toc.pdf | title page, dotted TOC with indentation, PDF outline |
| hidden-content.pdf | every hiding technique T1–T22 (canaries) + legitimate text that must survive |
| two-column.pdf | right column written first in the content stream |
| scanned.pdf | image only → OCR |
| scanned-with-ocr-layer.pdf | image + invisible OCR layer → must be kept |
| encrypted-user-password.pdf | user password `open-sesame` |
| copy-restricted.pdf | copying disallowed; owner password `owner-only` |
| unicode-normalization.pdf | ligatures, umlauts, accents, soft hyphen, standalone punctuation |
| not-a-pdf.pdf / truncated.pdf | invalid input |
| perf-200-pages.pdf | performance and header-filter regression guard |

Regenerate: `make fixtures` (needs Python venv, see `scripts/fixtures/requirements.txt`).
Validate: `make fixtures-verify` — proves every canary exists in the source and every
expectation is achievable, using extractors independent of PDFKit.

## 5. Manual QA checklist (TC-M01/M02)
1. Drag `simple-structured.pdf` onto the window → result in < 2 s; outline shows 6 rows.
2. Open `encrypted-user-password.pdf` → wrong password shows error → `open-sesame` works.
3. Open `copy-restricted.pdf` → owner password sheet → `owner-only` works.
4. Open `perf-200-pages.pdf` → Cancel at ~30 % → back to Import within 1 s.
5. `hidden-content.pdf` → report shows hidden words, invisible characters, repeated lines,
   inventory (metadata keys, XMP, 3 annotations, 1 attachment); redact the UUID; save as
   Markdown, HTML and text; open each file in a text editor and search for "CANARY" → none.
6. Save the same document twice → files identical (`cmp`).
7. VoiceOver walk-through of Import → Result; keyboard-only on macOS.
8. iPhone: choose from Files, save to Files "On My iPhone"; iPad: drag from Files app.
