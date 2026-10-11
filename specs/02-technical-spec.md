# 02 · Technical specification

Companion documents: hidden-content rules in `03-sanitization-spec.md`, screens in
`04-ui-spec.md`, tests in `05-test-plan.md`, work breakdown in `06-tasks.md`,
decisions in `adr/`.

## 1. Architecture overview

```
┌──────────────────────────── App (SwiftUI, macOS + iOS) ────────────────────────────┐
│ ImportView → PasswordSheet → ProcessingView → ResultView(Outline · Preview · Report) │
│                     AppModel (@Observable, @MainActor state machine)                 │
└───────────────────────────────────┬────────────────────────────────────────────────┘
                                    │ AsyncThrowingStream<PipelineEvent>
┌───────────────────────────────────▼──────────── PDFCleanKit (Swift package) ────────┐
│ Pipeline: ExtractionPipeline (actor)                                                 │
│   1 Ingest ─ open, unlock, permissions, SourceInventory                              │
│   2 Per page ─ GlyphExtractor → GlyphFilter(off-page, tiny, rotated) → WordBuilder   │
│                → VisibilityFilter → OverlapDeduper → UnicodeSanitizer/Homoglyphs     │
│                → (OCR if no visible text)                                            │
│   3 Document ─ RepeatedContentFilter → ReadingOrder(XY-cut) → LineAssembler          │
│                → StructureAnalyzer(title, outline/TOC, headings, lists, paragraphs) │
│   4 Text ─ (words sanitised in stage 2) → final sanitise pass → IdentifierDetector   │
│   5 Output ─ Markdown/HTML/PlainText renderers → OutputVerifier → CleanFileWriter    │
└──────────────────────────────────────────────────────────────────────────────────────┘
          uses only: PDFKit · CoreGraphics · Vision · NaturalLanguage · Foundation
```

Rule: **only stage 1–2 touch PDFKit/CoreGraphics objects**, and only inside the
pipeline actor. Everything after stage 2 operates on `Sendable` value types and is
pure (unit-testable without PDFs).

## 2. Repository layout

```
PDFClean/
├─ CLAUDE.md                     # Claude Code project memory (read first)
├─ README.md
├─ Makefile                      # all build/test/verify entry points
├─ project.yml                   # XcodeGen definition → PDFClean.xcodeproj (generated, git-ignored)
├─ App/
│  ├─ Shared/                    # SwiftUI app code shared by both platforms
│  ├─ macOS/PDFClean.entitlements
│  └─ Resources/Localizable.xcstrings
├─ Packages/PDFCleanKit/
│  ├─ Package.swift
│  ├─ Sources/PDFCleanKit/       # Model/ Ingest/ Extraction/ Sanitize/ Layout/ Export/ Pipeline/
│  ├─ Sources/pdfclean/          # CLI (macOS)
│  └─ Tests/PDFCleanKitTests/    # unit + fixture tests; Fixtures/ (PDFs + manifest.json)
├─ specs/                        # this specification
├─ scripts/                      # check_offline.sh, check_specs.py, fixtures/, reference/
├─ .claude/                      # settings, slash commands, review agents
└─ .vscode/                      # tasks, launch, settings, extension recommendations
```

## 3. Toolchain

| Item | Choice |
|------|--------|
| IDE | Xcode 16+ (builds, simulators, signing) + VS Code with the Swift extension (editing, SwiftPM build/test/debug) |
| Language | Swift 6 language mode, strict concurrency complete |
| UI | SwiftUI (one code base; `#if os(macOS)` only where platform APIs differ) |
| Project | XcodeGen (`project.yml`) so the project file is reproducible from CLI (`make generate`) |
| Tests | Swift Testing (`import Testing`) in the package; XCUITest smoke tests optional (T-071) |
| Formatting | `swift format` (bundled with the toolchain), config `.swift-format` |
| Fixtures | Python 3 + reportlab/pikepdf (dev only), see `scripts/fixtures/` |

Deployment targets: macOS 14.0, iOS 17.0. Bundle ID prefix `com.maxbehzadi.pdfclean`
(change in `project.yml`).

## 4. Public API of PDFCleanKit

```swift
// MARK: Options
public struct ExtractionOptions: Sendable, Equatable, Codable {
    public enum OCRMode: String, Sendable, Codable { case auto, off, always }
    public var ocrMode: OCRMode = .auto
    public var ocrLanguages: [String] = ["en-US", "de-DE"]
    public var removeHeadersFooters = true          // FR-12
    public var removeRepeatedLines = true           // FR-16
    public var removeRotatedText = true             // FR-13
    public var normalizeLookalikes = true           // FR-15
    public var includeTOCPageNumbers = true         // FR-08
    public var includePageBreaks = false            // renders a thematic break between pages
    public init() {}
}

// MARK: Pipeline
public actor ExtractionPipeline {
    public init(options: ExtractionOptions = .init())
    /// Emits progress events and finally `.finished`. Throws `PipelineError`.
    /// Honors Task cancellation between pages (and inside OCR).
    public func run(fileURL: URL, password: String?) -> AsyncThrowingStream<PipelineEvent, Error>
}

public enum PipelineEvent: Sendable {
    case progress(PipelineProgress)
    case finished(ExtractedDocument)
}

public struct PipelineProgress: Sendable, Equatable {
    public enum Stage: String, Sendable { case opening, readingPages, checkingVisibility,
                                          recognizingText, analyzingLayout, cleaning, done }
    public var stage: Stage
    public var page: Int          // 1-based, 0 when not page-bound
    public var pageCount: Int
    public var fractionCompleted: Double   // 0...1, monotonic
}

public enum PipelineError: Error, Sendable, Equatable {
    case notAPDF, unreadablePDF
    case passwordRequired, wrongPassword
    case copyingNotPermitted
    case tooLarge(pages: Int, bytes: Int64)
    case emptyDocument                      // no text even after OCR
    case ocrFailed(page: Int)
    case outputVerificationFailed([OutputViolation])
    case cancelled
    case io(String)                          // message without paths or content
}

// MARK: Export
public enum ExportFormat: String, CaseIterable, Sendable { case markdown, html, plainText
    public var fileExtension: String { ... }  // "md", "html", "txt"
}
public struct ExportOptions: Sendable { public var redactedIdentifiers: Set<String> = []
                                        public var neutralFileName = false }
public struct DocumentExporter: Sendable {
    public func render(_ doc: ExtractedDocument, as: ExportFormat, options: ExportOptions) throws -> String // runs OutputVerifier
    public func suggestedFileName(originalName: String, format: ExportFormat, options: ExportOptions) -> String
}
public struct CleanFileWriter: Sendable {
    public func write(_ text: String, to url: URL) throws   // UTF-8, no BOM, LF, strip xattrs on macOS
}
```

## 5. Data model (all `Sendable`, `Equatable`, `Codable`)

```swift
public struct ExtractedDocument {
    public var blocks: [Block]
    public var report: SanitizationReport
    public var pageCount: Int
    public var dominantLanguage: String?          // NLLanguageRecognizer, BCP-47
}

public enum Block {
    case title(String)
    case heading(level: Int, text: String)                       // 1...4
    case paragraph(String)
    case listItem(ListItem)
    case tableOfContents(heading: String?, entries: [TOCEntry])
    case preformatted(String)                                    // table-like regions
    case pageBreak(page: Int)                                    // only if includePageBreaks
}
public struct ListItem { public var ordered: Bool; public var marker: String; public var level: Int; public var text: String }
public struct TOCEntry { public var level: Int; public var title: String; public var page: String? }

public struct SanitizationReport {
    public var removedHiddenWords = 0, removedTinyGlyphs = 0, removedOffPageWords = 0
    public var removedRotatedRuns = 0, removedOverlappingDuplicates = 0
    public var removedRepeatedLines = 0, removedHeaderFooterLines = 0
    public var removedInvisibleCodepoints = 0, removedPrivateUseCodepoints = 0
    public var normalizedHomoglyphs = 0, normalizedWhitespace = 0, normalizedLigatures = 0
    public var ocrPages: [Int] = []
    public var suspiciousIdentifiers: [IdentifierFinding] = []
    public var warnings: [ReportWarning] = []
    public var sourceInventory = SourceInventory()
}
public struct SourceInventory {
    public var pdfVersion: String = ""
    public var isEncrypted = false
    public var metadataKeys: [String] = []      // keys only, sorted; values never stored
    public var hasXMP = false, hasOutline = false, hasFormFields = false, hasJavaScript = false
    public var annotationCount = 0, embeddedFileCount = 0
}
public struct IdentifierFinding { public var text: String; public var kind: Kind; public var occurrences: Int
    public enum Kind: String { case uuid, hex, base64Token, jwt, email, keyPattern } }
public enum ReportWarning: String { case manyPages, ocrLowConfidence, unreadableCharacters, rtlBasicSupport }
```

Internal working types (package-internal, value types):

```swift
struct Glyph  { var text: String; var box: CGRect; var pageBox: CGRect; var fontSize: CGFloat; var isBold: Bool; var fontName: String }
struct Word   { var text: String; var box: CGRect; var pageBox: CGRect; var glyphs: [Glyph]; var fontSize: CGFloat; var isBold: Bool }
// box = display space (layout); pageBox = unrotated PDF page space (raster visibility test)
struct Line   { var page: Int; var words: [Word]; var box: CGRect; var fontSize: CGFloat; var isBold: Bool; var source: Source
               enum Source { case textLayer, ocr } }
struct PageContent { var index: Int; var cropBox: CGRect; var lines: [Line] }
```

All layout geometry is in **display space**: points, origin top-left of the crop box,
y downward, page rotation (`/Rotate`) applied. Only the raster visibility test uses
`pageBox` (unrotated page space, matching `drawPDFPage`). Conversions live in one
helper (`PageGeometry`) with unit tests.

## 6. Pipeline stages

### 6.1 Ingest (`Ingest/DocumentOpener.swift`)
1. Read the first 1024 bytes; no `%PDF-` → `notAPDF`. Size > 500 MB → `tooLarge`.
2. `PDFDocument(url:)` nil → `unreadablePDF`.
3. If `isLocked`: no password → `passwordRequired`; `unlock(withPassword:)` false → `wrongPassword`.
4. If not locked but `allowsCopying == false`: if a password was supplied and
   `unlock(withPassword:)` succeeds and `permissionsStatus == .owner` → continue;
   otherwise `copyingNotPermitted`.
5. `pageCount == 0` → `emptyDocument`; `> 2000` → `tooLarge`; `> 300` → warning `manyPages`.
6. Build `SourceInventory` from `document.documentRef` (`CGPDFDocument`):
   Info keys via `CGPDFDictionaryApplyBlock` on `cgDoc.info` (keys only);
   catalog entries `Metadata` (XMP), `Outlines`/`outlineRoot`, `AcroForm`,
   `Names → EmbeddedFiles` (count the name tree leaves), `Names → JavaScript`,
   `OpenAction` with `/S /JavaScript`; annotation count summed over pages
   (`page.annotations.count`); `majorVersion.minorVersion`.
7. The opened file is a private temporary copy (see §9.3).

### 6.2 Glyph extraction (`Extraction/GlyphExtractor.swift`)
For each page (sequential):
- `let s = page.string ?? ""`, `let attr = page.attributedString`. If `attr?.string != s`,
  use `PDFSelection.selectionsByLine()` on the crop box as a fallback path and log a
  counter (no content).
- Iterate **UTF-16 offsets** of `s` (`NSString` indexing — `characterBounds(at:)` uses
  UTF-16 indices). A surrogate pair forms one glyph whose box is the union of both
  offsets' bounds.
- Empty boxes: if the character is whitespace or a line break it is a **separator**;
  otherwise (zero-width/format characters such as U+200B, U+2060, U+FEFF, TAG
  characters) the glyph is **kept inside the current word** with no geometry, so
  "Visi⟨U+200B⟩ble" stays one word and the character is removed later by
  `UnicodeSanitizer`. Never split a word on an invisible character.
- Font: `attr.attribute(.font, at:)` → `PlatformFont` (`NSFont`/`UIFont` typealias):
  `pointSize`; bold if the symbolic traits contain bold **or** the PostScript name
  contains `Bold|Black|Heavy|Semibold|Demi`. Effective size = `min(pointSize,
  box.height / 0.7)` when both are available (guards against scaled text matrices).
- Convert boxes from page space to display space (crop-box origin, rotation).

### 6.3 Glyph-level filters (`Sanitize/GlyphFilter.swift`, before words exist)
Run on the glyph sequence in content order (details in `03-sanitization-spec.md` §2):
off-page glyphs, tiny glyphs (< 2 pt) and **rotated runs** are dropped here. Rotation
must be detected on glyph runs *before* word building: PDFKit reports rotated text as
axis-aligned boxes stepping diagonally, which the word builder would otherwise split
into single letters.

### 6.4 Words (`Extraction/WordBuilder.swift`)
- Split the remaining glyph sequence at separators; additionally split when the
  horizontal gap between consecutive non-empty glyph boxes > `wordGapFactor` (0.25) ×
  size or when the vertical centre jumps > 0.5 × glyph height (new line in content order).
- A word's box is the union of its non-empty glyph boxes; a word with no geometry
  (only zero-width glyphs) attaches to the preceding word on the same line.

### 6.4a Word-level filters (details in `03-sanitization-spec.md` §3–4)
`VisibilityFilter` (raster ink test on the exclusive area) → `OverlapDeduper`. Each
filter increments its report counter.

### 6.4b Word text sanitising (early, before any matching)
Immediately after 6.4a, every word's text goes through `UnicodeSanitizer` and
`HomoglyphNormalizer` (§6.8); words that become empty are dropped. This must happen
**before** repeated-content matching, outline/TOC matching and identifier detection —
otherwise a watermark that differs per page only by invisible characters would defeat
the repetition rule. A word-final U+00AD becomes `-` so the paragraph join (§6.7.4) can
still repair the hyphenation; a mid-word U+00AD is removed. OCR line text (§6.5) goes
through the same functions.

### 6.5 OCR (`Extraction/OCRRecognizer.swift`)
- Trigger (mode `.auto`): after filtering, the page has zero visible words **and** its
  raster has ink coverage > 0.5 % (blank pages are skipped). `.always` OCRs every page
  and **replaces** its text layer; `.off` never.
- Render the page (content only, no annotations) at 300 dpi grayscale → `CGImage`;
  `VNRecognizeTextRequest(recognitionLevel: .accurate, usesLanguageCorrection: true,
  recognitionLanguages: options.ocrLanguages, automaticallyDetectsLanguage: true)`;
  `VNImageRequestHandler(cgImage:).perform` (synchronous, inside the actor; check
  `Task.isCancelled` before and after).
- Each observation → one `Line` (`source: .ocr`) from `topCandidates(1)`, bounding box
  converted from normalised (origin bottom-left) to display space; font size estimate =
  box height × 0.75; `isBold = false`. Confidence < 0.5 on > 30 % of observations → warning
  `ocrLowConfidence`.
- Optional enhancement (T-093): on macOS 26/iOS 26 SDKs use Vision's document
  recognition (`RecognizeDocumentsRequest`) for paragraph/list structure, behind
  `#available` checks. Verify the API in the installed SDK before use.

### 6.6 Document-level filters
- `RepeatedContentFilter` (FR-12, FR-16) — see sanitisation spec §5. Needs all pages,
  so it runs after the per-page loop.

### 6.7 Layout (`Layout/`)
1. **Lines** (`LineAssembler`): cluster words into lines by vertical overlap (centre
   distance < 0.5 × median word height), then split a line where the horizontal gap >
   `columnGapFactor` (2.0) × font size (prevents merging across column gutters). Words
   in a line are ordered by x (descending x when > 50 % of the line's letters are RTL —
   Arabic/Hebrew scripts — and warning `rtlBasicSupport` is added once).
2. **Reading order** (`ReadingOrder`): recursive XY-cut per page. Split the set of line
   boxes at the widest horizontal whitespace band (cut across the page) or vertical
   whitespace gutter ≥ `minGutter` (12 pt) whose height covers ≥ 60 % of the region;
   prefer horizontal cuts when both exist. Leaves are ordered top-to-bottom, left-to-
   right (right-to-left for RTL-dominant pages). Two-column pages with a full-width title
   therefore read: title → left column → right column.
3. **Font statistics** (`FontStatistics`): body size = font size (rounded to 0.5 pt)
   with the most glyphs among text-layer lines (all lines, OCR included, when the
   document has no text-layer lines); body line spacing = median baseline
   distance between consecutive body lines in the same column.
4. **Structure** (`StructureAnalyzer`), in this order:
   - *Outline*: if `document.outlineRoot` has children, flatten to (title, depth ≤ 4,
     page). A line becomes a heading of that depth when its normalised text equals an
     outline title on the same page (normalisation: casefold, collapse spaces, strip
     trailing dots/numbers).
   - *TOC*: a page is a TOC page if it contains a line matching the TOC keyword regex
     `^(table of contents|contents|inhaltsverzeichnis|inhalt|sommaire|table des matières|índice|indice|فهرست( مطالب)?)$` (case-insensitive) or ≥ 40 % of its lines (min 4) match
     `^(?<title>.+?)[\s.·…_]{2,}(?<page>\d{1,4}|[ivxlcdm]{1,6})$`. Continuation pages
     follow while the ratio stays ≥ 40 %. Entries: level by indentation cluster (or
     numbering depth), wrapped entries (line without page number followed by one with)
     merged. The TOC heading line becomes `tableOfContents.heading`, not a document
     heading. TOC entries also act as heading hints (like the outline) for later pages.
   - *Title*: on the first page with text, the line(s) in the upper 50 % with the largest
     size if ≥ 1.4 × body size **and** that style (size ± 0.5 pt, weight) occurs on at most
     one later page (otherwise it is a recurring heading style, e.g. "Chapter 1…200");
     adjacent lines with the same size/weight are merged. Never derived from metadata.
   - *Headings* (lines not already assigned): candidate when (a) size ≥ 1.15 × body, or
     (b) bold, ≤ 12 words, no terminal period, and gap above ≥ 1.2 × body spacing, or (c)
     numbered pattern `^\d+(\.\d+)*\.?\s+\p{Lu}` and (a) or (b). Levels: distinct
     candidate sizes (rounded 0.5 pt) sorted descending → 1, 2, 3, 4…; bold-at-body-
     size → one level below the smallest size level (max 4). Numbering depth
     (`1`→1, `1.2`→2, `1.2.3`→3) breaks ties. Consecutive candidate lines with the same
     style and gap ≤ 1.3 × spacing merge into one heading.
   - *Lists*: first word matches bullet set `[•◦▪▫‣⁃●○■□–—\-*·]` or ordered
     `^\(?(\d{1,3}|[a-zA-Z]|[ivxlcdm]{1,6})[.)]$`. Following lines whose left edge aligns
     with the item text (± 3 pt) and that do not start a new marker are continuation
     lines. Level = indentation cluster index of the marker x.
   - *Preformatted*: ≥ 3 consecutive lines each containing ≥ 2 internal gaps > 2 × size
     (table-like) → `preformatted`, words separated by two spaces per gap.
   - *Paragraphs*: remaining lines in reading order. Start a new paragraph when: gap
     above > 1.4 × body spacing; font size changes > 0.5 pt or weight changes; first-
     line indent > 1 em relative to the column's left edge; or the previous line ended
     with `[.!?:;"”»)]` and was shorter than 70 % of the column width.
     Join rule: if the previous line ends with `-` or soft hyphen U+00AD preceded by a
     letter and the next starts with a lowercase letter → remove the hyphen, join without
     space; if it ends with `-` and the next starts with a digit/uppercase → keep the
     hyphen, no space; otherwise join with one space.
   - *Cross-page continuation*: when the last block of page *n* is a paragraph without
     terminal punctuation and the first body block of page *n+1* (after filters) is a
     paragraph starting with a lowercase letter, merge them using the join rule.
5. **Page breaks**: if `includePageBreaks`, insert `.pageBreak(page:)` between pages
   unless a paragraph continues across the break.

### 6.8 Text sanitising (`Sanitize/`)
`UnicodeSanitizer` then `HomoglyphNormalizer` (sanitisation spec §6–7) are pure,
idempotent `(String) -> (String, Counters)` functions. They run on word text (§6.4b,
where the report counters are accumulated) and once more on every final block text
(TOC entries, list markers and text, headings, title) as a defence-in-depth pass whose
counters must be zero — a non-zero count there is a bug and is logged
(`Log.event("sanitize.late", ...)`).

### 6.9 Identifiers (`Sanitize/IdentifierDetector.swift`)
Regexes (Swift `Regex`), applied on final block text, longest match wins, findings
deduplicated and sorted by first occurrence:
- uuid `\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b`
- jwt `\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b`
- hex `\b(?=[0-9a-fA-F]*[a-fA-F])(?=[0-9a-fA-F]*\d)[0-9a-fA-F]{16,}\b`
- base64Token `\b(?=[A-Za-z0-9+/_-]*[A-Z])(?=[A-Za-z0-9+/_-]*[a-z])(?=[A-Za-z0-9+/_-]*\d)[A-Za-z0-9+/_-]{24,}={0,2}`
- email `\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b`
- keyPattern `\b[A-Z0-9]{4,}(?:-[A-Z0-9]{4,}){2,}\b` (requires ≥ 1 digit)
Redaction (`ExportOptions.redactedIdentifiers`) replaces exact matches with `[REDACTED]`
in all blocks at render time; the model is not mutated.

### 6.10 Renderers (`Export/`)
Common: blocks separated by exactly one blank line; trailing whitespace trimmed; file
ends with a single `\n`; no comments, generator names, dates or metadata.

| Block | Markdown | HTML (inside `<main>`) | Plain text |
|-------|----------|------------------------|------------|
| title | `# T` | `<h1>T</h1>` | `T` + newline + `=` × len |
| heading L | `#` × (L+1) (max 6); `#` × L if no title | `<h{L+1}>` | text + newline + `-` × len for L=1; text otherwise |
| paragraph | text (escaped) | `<p>` | text |
| list item | `  ` × level + `- ` or `N. ` (original number) | `<ul>/<ol>` nesting | `  ` × level + `• ` / `N. ` |
| TOC | `## <heading or "Contents">` + nested `- title (p. N)` | `<nav><h2>…</h2><ol>…` | heading + indented lines `title … N` |
| preformatted | fenced ```` ``` ```` block | `<pre>` | text as is |
| page break | `---` | `<hr>` | blank line + `* * *` |

Markdown escaping: `\`, `` ` ``, `*`, `_`, `[`, `]`, `<`, `>` and `|` inside text with a
backslash; a line starting with `#`, `+`, `-`, `=`, `>` or `\d+[.)]` gets a leading `\`.
HTML: escape `& < > " '`; document skeleton:
`<!doctype html><html lang="{dominantLanguage|und}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>{title|Document}</title><style>{embedded print-friendly CSS}</style></head><body><main>…</main></body></html>`.
No scripts, no external resources, no other meta tags.

### 6.11 Verification and writing
- `OutputVerifier.verify(_ text: String, inventoryValues: [String]) -> [OutputViolation]`:
  flags any code point in the forbidden sets (sanitisation spec §6) except `\n` (and
  `\t` inside preformatted), any Zs other than U+0020, and any source metadata value
  (Info values and XMP text nodes, length ≥ 6, collected transiently at ingest and
  never stored in the report) that does not also occur in the document's visible words
  (after the hidden-content filters).
- `CleanFileWriter`: `Data(text.utf8)` (no BOM), atomic write, then on macOS
  `listxattr`/`removexattr` for every attribute (ignore `EPERM`), log the count removed.

## 7. Concurrency and cancellation
- `ExtractionPipeline` is an `actor`; PDFKit/CoreGraphics/Vision objects never cross its
  isolation boundary (use `@preconcurrency import PDFKit` if needed). Public results are
  value types.
- `run` returns an `AsyncThrowingStream`; the producer is a child `Task` stored by the
  stream's `onTermination` to cancel work when the consumer stops.
- Pages are processed sequentially (deterministic, bounded memory). Each page body is
  wrapped in `autoreleasepool` on Darwin to release rasters promptly.
- Cancellation checkpoints: before each page, before/after rendering, before/after OCR.
  Throw `PipelineError.cancelled`.

## 8. Error → message mapping (UI, localised)

| Error | Title | Message / action |
|-------|-------|------------------|
| notAPDF | Not a PDF | "Choose a file that ends in .pdf." |
| unreadablePDF | Can't read this PDF | "The file may be damaged. Try re-exporting it from the original app." |
| passwordRequired / wrongPassword | Password needed / Wrong password | password sheet |
| copyingNotPermitted | Copying is not allowed | "The author restricted text copying. Enter the owner password to continue." + sheet |
| tooLarge | Document too large | limits from NFR-06 |
| emptyDocument | No text found | "Even text recognition found nothing on these pages." |
| ocrFailed | Text recognition failed | page number |
| outputVerificationFailed | Internal safety check failed | "Nothing was saved. Please report this file type." |
| cancelled | — | return to import silently |
| io | Couldn't save the file | system description without paths |

## 9. App architecture (`App/Shared`)

### 9.1 State machine (`AppModel`, `@MainActor @Observable`)
```
idle ──open(url)──▶ preparing ──needs password──▶ awaitingPassword(kind: .user|.owner, retry: Bool)
  ▲                    │                              │ submit / cancel
  │                    ▼                              ▼
  ├──cancel/close── processing(PipelineProgress) ◀────┘
  │                    │ finished                 │ error
  │                    ▼                          ▼
  └──────────── result(ResultState) ─── failed(UserFacingError) ──retry/close──▶ idle
```
`ResultState` = document, selected export format, redaction set, selected outline id.

### 9.2 Views
`RootView` (switch on state) · `ImportView` (drop zone + open button + options link) ·
`PasswordSheet` · `ProcessingView` · `ResultView` (`OutlineSidebar`, `PreviewView`,
`ReportPanel`, `IdentifierList`, toolbar: format picker, Save, New) · `OptionsView`
(macOS `Settings` scene; iOS sheet) · `ErrorView`. Preview renders blocks natively with
SwiftUI `Text` styles (no web view); "Source" toggle shows the rendered export string
in a monospaced, selectable view.

### 9.3 Files and platform specifics
- Import: `.fileImporter(allowedContentTypes: [.pdf])` on both platforms, plus
  `.dropDestination(for: URL.self)` (macOS, iPadOS). Start security-scoped access,
  copy to `FileManager.default.temporaryDirectory/PDFClean/<random>/input.pdf`, stop
  access, process the copy. Delete the job folder on finish/cancel/reset and purge
  the whole `PDFClean` temp folder at launch.
- Export: `.fileExporter(isPresented:document:contentType:defaultFilename:)` with a
  `CleanTextDocument: FileDocument` whose `fileWrapper` returns
  `FileWrapper(regularFileWithContents: Data(text.utf8))` (no attributes). On macOS,
  after a successful export, run `CleanFileWriter.stripExtendedAttributes(at:)` on the
  returned URL (best effort).
- UTTypes: markdown `UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText`,
  `.html`, `.plainText`.
- macOS: window min size 900 × 600; menu commands Open (⌘O), Save (⌘S), New (⌘N);
  `Settings` scene for options.
- Entitlements (macOS): `com.apple.security.app-sandbox = true`,
  `com.apple.security.files.user-selected.read-write = true`. Nothing else.

## 10. Constants (single source: `Sources/PDFCleanKit/Constants.swift`)

| Name | Value | Used by |
|------|-------|---------|
| renderScale | 2.0 | VisibilityFilter raster (pt → px) |
| inkDelta | 40 / 255 | ink pixel test |
| minInkFraction | 0.01 | visible word threshold |
| neighbourPad | 0.25 × box height | exclusive-area masking |
| minExclusiveShare | 0.30 | fall back to full box |
| minFontSize | 2.0 pt | tiny glyph filter |
| maxBaselineAngle | 10° | rotated runs |
| duplicateIoU | 0.7 | overlap dedupe |
| marginBand | 7 % of page height | header/footer band |
| headerFooterMaxSizeFactor | 1.05 × body | header/footer font cap |
| repeatedLineMaxSizeFactor | 1.15 × body | Rule B font cap (headings never removed) |
| offPageMinInside | 0.5 of glyph area | off-page glyphs |
| diagonalMaxStep | 2.0 × size | rotated-run neighbour distance |
| minRotatedRun | 3 glyphs | rotated runs |
| repeatRatio | 0.5 (and ≥ 2 pages) | repeated lines |
| positionTolerance | 2 % of page size | same-position test |
| wordGapFactor | 0.25 × size | word split |
| columnGapFactor | 2.0 × size | line split at gutters |
| minGutter | 12 pt | XY-cut |
| titleSizeFactor | 1.4 × body | title |
| headingSizeFactor | 1.15 × body | headings |
| headingGapFactor | 1.2 × spacing | bold-candidate heading rule (§6.7.4b) |
| headingMergeGapFactor | 1.3 × spacing | heading line merge (§6.7.4) |
| paragraphGapFactor | 1.4 × spacing | paragraphs |
| shortLineFactor | 0.7 × column width | paragraph end |
| tocLineRatio | 0.4 (min 4 lines) | TOC pages |
| ocrDPI | 300 | OCR render |
| ocrMinInkCoverage | 0.005 | OCR trigger |
| maxPages / maxBytes / warnPages | 2000 / 500 MB / 300 | NFR-06 |

## 11. Logging
All logging goes through `Log.event(_ name: StaticString, _ values: (StaticString, Int)...)`
(`Sources/PDFCleanKit/Log.swift`, already in the scaffold): event names and keys are
static strings, values are integers — document text, file names, paths and metadata
values cannot be logged by construction. `scripts/check_offline.sh` rejects `print`,
`NSLog`, `os_log` and `Logger(` anywhere else (the CLI target may print its output).

## 12. Performance budget (per text page, Release, M1)
Glyph extraction ≤ 20 ms · raster at 2× ≤ 25 ms · visibility ≤ 15 ms · layout + text
≤ 10 ms (amortised) ⇒ ≈ 70 ms/page. OCR page ≈ 1–2 s.

## 13. Security notes
- PDFKit parses untrusted input; we never execute JavaScript, follow links, open
  attachments or load remote resources.
- No `WKWebView` for preview (avoids any network surface).
- Output is plain UTF-8 text; HTML output contains no scripts and escapes all text.
