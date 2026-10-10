# 03 · Sanitisation specification (hidden content)

## 1. Principle: build, don't copy

The output file is **generated** from the document model (`[Block]`). Nothing is
copied from the PDF container, so container-level carriers (Info dictionary, XMP,
trailer `/ID`, annotations, form fields, attachments, JavaScript, outline targets,
page labels, structure tree, file name) cannot reach the output by construction.
What remains to defend is the **text layer** itself, handled in this document.

### Threat catalogue

| # | Technique | Where it hides | Defence | Stage | Fixture canary | Counter |
|---|-----------|----------------|---------|-------|----------------|---------|
| T1 | Info dictionary / custom keys | trailer Info | not copied; keys listed | ingest | CANARY-META-* | inventory |
| T2 | XMP packet / DocumentID | catalog Metadata | not copied | ingest | CANARY-XMP-* | inventory |
| T3 | Comments, links | annotations | not copied, not rendered | ingest/raster | CANARY-ANNOT-COMMENT, CANARY-LINK | inventory |
| T4 | Form values | AcroForm widgets | not rendered → no ink | raster | CANARY-FORM-VALUE | removedHiddenWords |
| T5 | Attachments | EmbeddedFiles | not copied | ingest | CANARY-ATTACH-PAYLOAD | inventory |
| T6 | Invisible render mode (Tr 3) | text layer | no ink | §3 | CANARY-INVISIBLE-RENDER | removedHiddenWords |
| T7 | White-on-white / same colour as background | text layer | no ink | §3 | CANARY-WHITE-TEXT, CANARY-INLINE-WHITE, CANARY-TIGHT-WHITE | removedHiddenWords |
| T8 | Covered by opaque shape | text layer | no ink | §3 | CANARY-COVERED-TEXT | removedHiddenWords |
| T9 | Clipped away | text layer | no ink | §3 | CANARY-CLIPPED | removedHiddenWords |
| T10 | Outside crop box | text layer | geometry | §2.1 | CANARY-OFFPAGE | removedOffPageWords |
| T11 | Microscopic text | text layer | font size | §2.2 | CANARY-TINY-TEXT | removedTinyGlyphs |
| T12 | Rotated / diagonal watermark | text layer | baseline angle | §2.3 | CANARY-ROTATED | removedRotatedRuns |
| T13 | Per-recipient line on every page | text layer (visible) | repetition | §5 | CANARY-WATERMARK | removedRepeatedLines |
| T13b | Same line varied per page only by invisible characters | text layer (visible) | sanitise words *before* repetition matching | §5, tech §6.4b | CANARY-ZWVARIANT | removedRepeatedLines |
| T14 | Fingerprint in header/footer | text layer (visible) | margin repetition | §5 | CANARY-FOOTER-ID | removedHeaderFooterLines / removedRepeatedLines |
| T15 | Zero-width / format characters | text layer, ToUnicode | Unicode filter | §6 | U+200B… | removedInvisibleCodepoints |
| T16 | Unicode TAG "ASCII smuggling" | ToUnicode CMap | Unicode filter (+ tiny filter when zero-size) | §6 | U+E0043… | removedInvisibleCodepoints / removedTinyGlyphs |
| T17 | Bidi controls | text layer | Unicode filter | §6 | U+202A, U+2066… | removedInvisibleCodepoints |
| T18 | Homoglyph substitution (Cyrillic/Greek in Latin words) | text layer | homoglyph map | §7 | U+0430, U+043E | normalizedHomoglyphs |
| T19 | Whitespace-pattern fingerprint (NBSP, thin, ideographic, runs) | text layer | whitespace normalisation | §6 | U+00A0, U+2009, U+3000 | normalizedWhitespace |
| T20 | Fake-bold / duplicated overlay | text layer | overlap dedupe | §4 | "Summary" ×2 | removedOverlappingDuplicates |
| T21 | Private-use glyphs, variation-selector steganography | text layer | Unicode filter | §6 | unit tests | removedPrivateUseCodepoints / removedInvisibleCodepoints |
| T22 | Visible IDs (UUID, key, e-mail) | visible text | user-controlled redaction | tech spec §6.9 | 3f2a9c1e-… | suspiciousIdentifiers |

## 2. Glyph-level filters (`GlyphFilter`)

Input: glyphs of one page in content order with display-space boxes.

### 2.1 Off-page
Drop a glyph whose box has < 50 % of its area inside the crop box. Count one
`removedOffPageWords` per maximal run of consecutive dropped non-space glyphs.

### 2.2 Tiny
Drop glyphs with effective font size < `minFontSize` (2.0 pt). Count each glyph in
`removedTinyGlyphs`.

### 2.3 Rotated runs
Walk consecutive non-space glyphs with non-empty boxes. For each consecutive pair
compute the centre-to-centre vector *v*; the pair is *diagonal* when
`10° < |atan2(v.dy, v.dx)| < 170°` and `|v| < 2 × size`. A maximal run of ≥ 3 glyphs
joined by diagonal pairs is rotated → drop the run, `removedRotatedRuns += 1`.
Exception: runs where ≥ 80 % of glyphs are CJK/Hangul/Kana (vertical writing) are kept
and ordered top-to-bottom. Option `removeRotatedText = false` keeps rotated runs as
separate lines.

## 3. Visibility filter (`VisibilityFilter`)

Executable reference with identical constants: `scripts/reference/visibility_reference.py`.

### 3.1 Raster
- Create an 8-bit grayscale `CGContext` (`CGColorSpaceCreateDeviceGray`, no alpha) of
  size `ceil(cropBox.size × renderScale)`; fill white.
- Transform: `scaleBy(renderScale)`, `translateBy(-cropBox.minX, -cropBox.minY)`; draw
  `context.drawPDFPage(page.pageRef!)`. This draws page **content only** —
  annotations, widgets and form appearances are not drawn (T3/T4).
- Draw in **unrotated page space**; the word boxes for this test are therefore taken
  *before* the display-space rotation (keep both boxes on `Word`).
- Bitmap row 0 is the **top** of the image: pixel row = `height − 1 − y_px`.

### 3.2 Per-word decision
Words that survived §2 are the *maskers*. For each word *w*:
1. `region` = raster pixels of *w*'s box (clamped to the page), **no inset** (insetting
   loses punctuation such as `_` or `.`).
2. `mask` = all pixels of `region`, minus pixels covered by every other masker's box
   expanded vertically by `neighbourPad` (0.25 × that box's height). This removes ink
   that belongs to neighbouring lines (descenders, tight leading) — required to catch
   white text squeezed under a visible line (CANARY-TIGHT-WHITE).
3. If `mask` keeps ≥ `minExclusiveShare` (30 %) of `region`, measure only masked pixels;
   otherwise (fully overlapped, e.g. fake bold) measure the whole region.
4. `background` = median luminance of the region's border pixels.
5. `ink` = share of measured pixels with `|luminance − background| > inkDelta` (40/255).
6. Visible ⇔ `ink ≥ minInkFraction` (1 %). Otherwise drop the word,
   `removedHiddenWords += 1`.

Evidence (reference run on all fixtures): visible words score 0.27–0.39, all hidden
canaries 0.000, punctuation-only words visible, OCR text layer over a scan visible,
zero false positives on `simple-structured`, `toc`, `two-column`,
`unicode-normalization`, `perf-200-pages`.

### 3.3 Known limits (documented, tested where possible)
- Hidden text placed exactly over other visible ink (e.g. white text over a dark photo
  region that happens to contain ink) is judged visible. Mitigation backlog T-092.
- Very low-contrast but intentionally visible text (< 16 % luminance difference) is
  dropped; acceptable for v1 — such text is not readable either.

## 4. Overlap dedupe (`OverlapDeduper`)
Two visible words on the same page with equal text (after NFC) whose boxes have IoU ≥
0.7 are duplicates; keep the first in content order. `removedOverlappingDuplicates += 1`
per removed word. Fixture: the double-drawn "Summary" heading appears exactly once.

## 5. Repeated content (`RepeatedContentFilter`, after all pages)
Let *N* = page count; skip when *N* < 2. Lines are compared on two keys:
- `exactKey` = NFC text with collapsed spaces;
- `digitKey` = lower-cased `exactKey` with every digit run replaced by `#` and roman
  numerals at word boundaries replaced by `#`.
Positions are relative: `(x/pageWidth, y/pageHeight)` of the line box origin.
Rules run in the order A → C → B; a line removed by one rule is not counted again.
Keys are computed on **sanitised** word text (tech spec §6.4b).

- **Rule A — headers/footers** (`removeHeadersFooters`): line lies in the top or bottom
  `marginBand` (7 % of page height) and its font size ≤ 1.05 × body size. If its
  `digitKey` occurs in the band on ≥ max(2, ⌈0.5 N⌉) pages, remove every occurrence
  → `removedHeaderFooterLines`.
- **Rule B — repeated lines/watermarks** (`removeRepeatedLines`): anywhere on the page,
  font size ≤ 1.15 × body (headings are never removed by this rule), same `exactKey`
  at the same relative position (± 2 % in x and y) on ≥ max(2, ⌈0.5 N⌉) pages → remove
  all occurrences → `removedRepeatedLines`.
- **Rule C — page numbers**: a line in the margin band that matches
  `^(page|seite|p\.|s\.)?\s*(\d{1,4}|[ivxlcdm]{1,6})(\s*(of|von|/|de|di)\s*\d{1,4})?$`
  or `^[-–—]\s*\d{1,4}\s*[-–—]$` (case-insensitive) is removed even when not repeated
  → `removedHeaderFooterLines`.

Regression guards: `perf-200-pages` keeps all 200 "Chapter N" headings (16 pt > cap);
`simple-structured` loses "ACME Corp · Internal Use" and "Page n of 2".

## 6. Unicode sanitiser (`UnicodeSanitizer`, pure function)

Applied to every word right after the visibility filters (tech spec §6.4b) — before
repetition, outline and TOC matching — and again, idempotently, to every final block
text. Steps in order:

1. **PUA bullets** — map common symbol-font private-use bullets to `•`:
   U+F0B7, U+F0A7, U+F076, U+F0D8, U+F0FC, U+F06E.
2. **Ligatures** — U+FB00 ff, U+FB01 fi, U+FB02 fl, U+FB03 ffi, U+FB04 ffl,
   U+FB05 ſt→st, U+FB06 st (`normalizedLigatures`).
3. **Remove** (count `removedInvisibleCodepoints` unless noted):
   - C0 controls U+0000–U+001F except LF (and TAB inside `preformatted`), DEL U+007F,
     C1 U+0080–U+009F;
   - soft hyphen U+00AD — except at the very end of a word, where it becomes `-` so the paragraph join can repair the line-break hyphenation (tech spec §6.4b);
   - U+034F CGJ; U+061C ALM; U+115F, U+1160, U+3164, U+FFA0 (Hangul fillers); U+17B4, U+17B5; U+180B–U+180F;
   - U+200B ZWSP; U+200C ZWNJ and U+200D ZWJ **except** in the contexts of §6.1;
   - U+200E LRM, U+200F RLM, U+202A–U+202E (embeddings/overrides), U+2066–U+2069 (isolates);
   - U+2060–U+2064 (word joiner, invisible operators), U+206A–U+206F;
   - U+FEFF BOM/ZWNBSP; U+FFF9–U+FFFC (interlinear annotation, object replacement);
   - U+FE00–U+FE0D variation selectors (U+FE0E/U+FE0F kept only directly after an
     emoji/symbol code point), U+E0100–U+E01EF variation selectors supplement;
   - U+E0000–U+E007F TAG block;
   - U+FFFD replacement character (also add warning `unreadableCharacters`);
   - private use U+E000–U+F8FF, U+F0000–U+FFFFD, U+100000–U+10FFFD → `removedPrivateUseCodepoints`;
   - unassigned (general category Cn) and any remaining Cf not listed above.
4. **Whitespace** — every Zs character (U+00A0, U+1680, U+2000–U+200A, U+202F,
   U+205F, U+3000) and TAB (outside preformatted) → U+0020; LF inside a block → U+0020;
   collapse runs of spaces; trim (`normalizedWhitespace` counts changed characters).
5. **NFC** normalisation (not NFKC: keeps ², ½, ™, accents as written).

### 6.1 Context exceptions (keep ZWNJ/ZWJ)
- ZWNJ U+200C / ZWJ U+200D are kept when both neighbours are letters of the **same**
  script and that script is one of Arabic, Syriac, Thaana, Devanagari, Bengali,
  Gurmukhi, Gujarati, Oriya, Tamil, Telugu, Kannada, Malayalam, Sinhala, Khmer,
  Myanmar (e.g. Persian "می⟨U+200C⟩خواهم" keeps its ZWNJ).
- ZWJ is kept between two emoji code points (emoji ZWJ sequences).
- Never kept between Latin, Greek, Cyrillic letters or digits.

## 7. Homoglyph normaliser (`HomoglyphNormalizer`, option `normalizeLookalikes`)

Operates per word token (`\p{L}[\p{L}\p{M}]*`).
1. Fullwidth ASCII U+FF01–U+FF5E → U+0021–U+007E; Mathematical Alphanumeric Symbols
   U+1D400–U+1D7FF → their NFKC (plain) letter/digit. Always applied.
2. Mixed-script rule: if the token contains ≥ 1 Latin letter **and** ≥ 1 Cyrillic or
   Greek letter, and **every** Cyrillic/Greek letter in it has a mapping below, replace
   them → `normalizedHomoglyphs` (one per replaced character). Tokens written entirely
   in Cyrillic or Greek are never changed.

| Script | Look-alike → Latin |
|--------|--------------------|
| Cyrillic lower | а a, е e, о o, р p, с c, у y, х x, і i, ј j, ѕ s, ԁ d, ԛ q, ԝ w, һ h, ӏ l |
| Cyrillic upper | А A, В B, Е E, К K, М M, Н H, О O, Р P, С C, Т T, Х X, У Y, І I, Ј J, Ѕ S |
| Greek lower | ο o, ν v, ι i, κ k (only in mixed tokens) |
| Greek upper | Α A, Β B, Ε E, Ζ Z, Η H, Ι I, Κ K, Μ M, Ν N, Ο O, Ρ P, Τ T, Υ Y, Χ X |

## 8. Out of scope / backlog
- T-092: cross-check text-layer words that sit over images against Vision OCR of the
  same region and drop words OCR cannot see (catches tokens hidden in scan layers).
- Steganography in images, font glyph shapes or kerning/word-spacing micro-patterns
  (output re-flows text, which already destroys spacing patterns).
- Visible content that is not repeated (e.g. a single "Prepared for Jane Doe" line):
  surfaced via identifier detection only when it matches a pattern; otherwise the user
  edits the output.

## 9. Verification (`OutputVerifier`)
Forbidden in exported strings: every code point removed by §6 step 3 (outside the
§6.1 contexts), any Zs other than U+0020, C0 controls other than LF (TAB only inside
fenced/`<pre>` blocks), and any source metadata *value* (Info values and XMP text, ≥ 6
characters, held in memory only) that does not also appear in the **visible** words of
the document (after §2–§5 filters). A violation throws `outputVerificationFailed` and nothing is written.
