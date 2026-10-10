# ADR-003 · Output formats: Markdown (default), HTML, plain text

**Status:** Accepted · **Date:** 2026-10-10

## Context
Users want "a layout file" with title, headings, TOC and paragraphs that uploads cleanly
to AI tools. Options: Markdown, HTML, plain text, DOCX, regenerated PDF.

## Decision
v1 exports Markdown (default — best for AI tools and keeps structure), self-contained
HTML (readable/printable layout) and plain text. DOCX and PDF are backlog (T-090/T-091).

## Consequences
+ Text formats carry no hidden containers: what you see in an editor is the whole file.
+ HTML can be printed to PDF by the user if a PDF is needed.
− DOCX and PDF writers add container metadata (docProps, Info/XMP via CoreGraphics);
  doing them cleanly needs custom writers — deferred until there is demand.
