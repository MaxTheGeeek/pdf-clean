# ADR-002 · Detect hidden text by rasterising the page

**Status:** Accepted · **Date:** 2026-10-10

## Context
Hidden text uses many techniques: render mode 3, white-on-white, covered by shapes,
clipping, soft masks, transparency. PDFKit gives characters and boxes but no render
mode, colour or clip state. Parsing content streams with `CGPDFScanner` would require a
full graphics-state interpreter (clipping paths, XObjects, soft masks) — large and
error-prone.

## Decision
Render the page content (no annotations) to an 8-bit grayscale bitmap at 2× and judge
each word by the share of ink pixels in the part of its box not covered by other words
(exclusive area). Parameters are fixed in `Constants.swift` and mirrored by the
executable reference `scripts/reference/visibility_reference.py`.

## Evidence
On all fixtures the reference gives visible words 0.27–0.39 ink, hidden canaries 0.000
(white, invisible mode, covered, clipped, inline white word, white text squeezed under a
descender line), no false positives on clean documents, and keeps invisible OCR layers
over scanned images. Insetting the box was rejected (drops `_`), as was measuring the
full box (descenders of the line above leak 4.5 % ink into hidden text).

## Consequences
+ One mechanism covers every current and future "make it not render" trick.
+ Cost ≈ 25 ms raster + 15 ms test per page.
− Hidden text placed over other ink is judged visible (backlog T-092).
