# ADR-001 · Native Swift app on Apple frameworks

**Status:** Accepted · **Date:** 2026-10-10

## Context
The app must run fully offline on macOS **and iOS/iPadOS**, read PDFs, OCR scans and
present a simple UI. Candidates: (a) SwiftUI + PDFKit/Vision, (b) Electron/Tauri with
pdf.js + Tesseract, (c) Python (PyMuPDF) desktop app, (d) .NET MAUI with a PDF library.

## Decision
SwiftUI multiplatform app with a Swift package `PDFCleanKit` using only Apple
frameworks: PDFKit (text + geometry), CoreGraphics (raster), Vision (on-device OCR),
NaturalLanguage (language id). No third-party runtime dependencies.

## Consequences
+ One code base for macOS and iOS; iOS rules out (b) and (c) in practice.
+ PDFKit, CoreGraphics and Vision ship with the OS: offline by default, no licences
  (PyMuPDF is AGPL; Tesseract models add 10s of MB), small binary.
+ App Sandbox lets the OS enforce "no network" on macOS.
− PDFKit does not expose text render mode or fill colour → hidden-text detection by
  rasterisation (ADR-002).
− Heuristics must be tuned against PDFKit's character model, not pdfminer's; the Python
  scripts are dev-only references.
