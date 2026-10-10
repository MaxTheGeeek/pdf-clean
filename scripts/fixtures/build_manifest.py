#!/usr/bin/env python3
"""
Writes Packages/PDFCleanKit/Tests/PDFCleanKitTests/Fixtures/manifest.json —
the machine-readable acceptance criteria for every fixture (see specs/05-test-plan.md).

Field reference (all optional except id/file):
  password              password to supply when opening
  expectError           PipelineError case name the pipeline must throw
  expectNoCrash         only requirement: no crash, either success or a thrown PipelineError
  title                 expected .title block text
  headings              [[level, text], ...] document headings in order (excludes the TOC heading)
  tocEntries            [[level, text, page], ...]
  listItems             [{"ordered": bool, "text": str}, ...] in order
  mustContain           phrases that must appear in the Markdown output (whitespace-normalised)
  mustContainAfterFiltering same as mustContain, but only achievable after visibility filtering,
                        header/footer removal or cross-page joining (the independent verifier skips these)
  mustNotContain        strings that exist in the SOURCE and must not reach the output
  mustNotContainDerived strings that would only appear through bad joining (not in the source)
  mustNotContainCodepoints  hex code points that must not appear in any output
  occurrences           {text: exact count} in the output
  orderedPhrases        phrases that must appear in this order
  separateParagraphs    [[a, b], ...] a and b must be in different paragraph blocks
  ocrPages              1-based pages that must go through OCR (exactly this set)
  ocrTolerant           compare mustContain/title using lowercase alphanumerics only
  suspiciousIdentifiers identifiers the detector must list (not removed by default)
  reportAtLeast         {SanitizationReport counter: minimum}
  reportExactly         {SanitizationReport counter: exact value} (false-positive guards)
  sourceInventory       expected SourceInventory values (hasXMP, hasOutline, hasFormFields,
                        embeddedFileCount, minAnnotationCount, metadataKeysInclude)
  maxSeconds            upper bound for pipeline wall time on Apple silicon (Debug: x3)
"""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / "Packages/PDFCleanKit/Tests/PDFCleanKitTests/Fixtures/manifest.json"

CLEAN = {"removedHiddenWords": 0, "removedTinyGlyphs": 0, "removedRotatedRuns": 0, "removedOffPageWords": 0}

CANARIES = [
    "CANARY-WHITE-TEXT", "CANARY-INVISIBLE-RENDER", "CANARY-COVERED-TEXT", "CANARY-TINY-TEXT",
    "CANARY-OFFPAGE", "CANARY-CLIPPED", "CANARY-WATERMARK", "CANARY-ROTATED", "CANARY-FOOTER-ID",
    "CANARY-ANNOT-COMMENT", "CANARY-LINK", "CANARY-FORM-VALUE", "CANARY-META-TITLE",
    "CANARY-META-AUTHOR", "CANARY-META-KEYWORDS", "CANARY-META-CUSTOM", "CANARY-XMP-DOCID",
    "CANARY-XMP-DESCRIPTION", "CANARY-ATTACH-PAYLOAD", "CANARY-INLINE-WHITE", "CANARY-TIGHT-WHITE", "CANARY-ZWVARIANT",
]

fixtures = [
    {
        "id": "simple-structured",
        "file": "simple-structured.pdf",
        "covers": ["FR-04", "FR-06", "FR-07", "FR-09", "FR-10", "FR-12"],
        "title": "Quarterly Infrastructure Report",
        "headings": [[1, "1 Introduction"], [2, "1.1 Scope"], [2, "1.2 Priorities"],
                     [1, "2 Results"], [2, "2.1 Outcomes"]],
        "listItems": [
            {"ordered": False, "text": "Migrate legacy services to containers"},
            {"ordered": False, "text": "Consolidate monitoring dashboards into a single view for the operations team"},
            {"ordered": True, "text": "Alpha rollout in the staging region"},
            {"ordered": True, "text": "Beta rollout in the production region"},
        ],
        "mustContain": [
            "The new platform improves resilience across our infrastructure and reduces operating costs significantly.",
            "Availability rose to ninety-nine point nine five percent for the quarter.",
        ],
        "mustContainAfterFiltering": [
            "and the migration continued without major incidents across all regions.",
        ],
        "mustNotContain": ["ACME Corp", "Page 1 of 2", "Page 2 of 2"],
        "mustNotContainDerived": ["infra- structure", "infra-structure", "migration\n\ncontinued"],
        "separateParagraphs": [["This report summarises", "A second paragraph begins"]],
        "ocrPages": [],
        "reportAtLeast": {"removedHeaderFooterLines": 4},
        "reportExactly": CLEAN,
    },
    {
        "id": "toc",
        "reportExactly": CLEAN,
        "file": "toc.pdf",
        "covers": ["FR-06", "FR-07", "FR-08"],
        "title": "Handbook of Offline Tools",
        "tocEntries": [[1, "1 Getting Started", 3], [2, "1.1 Installation", 3], [2, "1.2 Configuration", 3],
                       [1, "2 Advanced Usage", 4], [2, "2.1 Batch Mode", 4]],
        "headings": [[1, "1 Getting Started"], [2, "1.1 Installation"], [2, "1.2 Configuration"],
                     [1, "2 Advanced Usage"], [2, "2.1 Batch Mode"]],
        "mustContain": ["Edition 2026", "Batch mode processes a folder of documents sequentially."],
        "mustNotContainDerived": [".....", ". . . ."],
        "ocrPages": [],
        "sourceInventory": {"hasOutline": True, "hasXMP": False, "embeddedFileCount": 0},
    },
    {
        "id": "hidden-content",
        "file": "hidden-content.pdf",
        "covers": ["FR-13", "FR-14", "FR-15", "FR-16", "FR-17", "FR-18", "FR-19", "FR-22"],
        "title": "Confidential Briefing",
        "headings": [[1, "Summary"], [1, "Details"]],
        "mustContain": [
            "This is the visible briefing text that must survive extraction.",
            "Visible paragraph text with hidden marks.",
            "Tag smuggling test sentence.",
            "Bidi control characters are removed.",
            "The password policy applies to all staff.",
            "Spacing test with odd whitespace.",
            "Reference: 3f2a9c1e-77b4-4c2e-9d1a-0b6e5f4a3c21",
            "The final visible sentence on page one.",
            "Typography quickly gauges jumpy glyph descenders.",
            "Second page visible content is preserved as well.",
        ],
        "mustContainAfterFiltering": ["Inline check: alpha omega closes the line."],
        "mustNotContain": CANARIES + ["max@example.com", "7F3A-99X2", "Copy #00417", "Northwind Traders"],
        "mustNotContainDerived": ["SummarySummary", "Summary Summary"],
        "mustNotContainCodepoints": ["200B", "200C", "2060", "FEFF", "202A", "202C", "2066", "2069",
                                     "3000", "2009", "00A0", "0430", "043E",
                                     "E0041", "E0043", "E004E", "E0052", "E0059"],
        "occurrences": {"Summary": 1},
        "suspiciousIdentifiers": ["3f2a9c1e-77b4-4c2e-9d1a-0b6e5f4a3c21"],
        "ocrPages": [],
        "reportAtLeast": {
            "removedHiddenWords": 7,
            "removedTinyGlyphs": 7,
            "removedOffPageWords": 1,
            "removedInvisibleCodepoints": 4,
            "removedRepeatedLines": 4,
            "removedHeaderFooterLines": 2,
            "removedRotatedRuns": 2,
            "normalizedHomoglyphs": 2,
            "removedOverlappingDuplicates": 1,
        },
        "sourceInventory": {
            "hasXMP": True, "embeddedFileCount": 1, "minAnnotationCount": 3, "hasFormFields": True,
            "metadataKeysInclude": ["Author", "Creator", "Keywords", "Producer", "Title", "TrackingID"],
        },
    },
    {
        "id": "two-column",
        "reportExactly": CLEAN,
        "file": "two-column.pdf",
        "covers": ["FR-11"],
        "title": "Two Column Article",
        "orderedPhrases": ["Left column begins", "Left column ends", "Right column begins", "Right column ends"],
        "ocrPages": [],
    },
    {
        "id": "scanned",
        "file": "scanned.pdf",
        "covers": ["FR-05"],
        "ocrTolerant": True,
        "title": "Scanned page sample",
        "mustContain": ["must be recovered with offline OCR on the device.",
                        "No network access is ever required for recognition."],
        "ocrPages": [1],
    },
    {
        "id": "scanned-with-ocr-layer",
        "reportExactly": CLEAN,
        "file": "scanned-with-ocr-layer.pdf",
        "covers": ["FR-04", "FR-13"],
        "title": "Searchable scan sample",
        "mustContain": ["This page was produced as an image so that the text",
                        "No network access is ever required for recognition."],
        "ocrPages": [],
        "comment": "Invisible OCR text over a scanned image is legitimate and MUST be kept: ink exists under it.",
    },
    {
        "id": "encrypted-ok",
        "file": "encrypted-user-password.pdf",
        "covers": ["FR-02"],
        "password": "open-sesame",
        "mustContain": ["Encrypted content unlocked with the correct password."],
        "ocrPages": [],
    },
    {"id": "encrypted-missing-password", "file": "encrypted-user-password.pdf", "covers": ["FR-02"],
     "expectError": "passwordRequired"},
    {"id": "encrypted-wrong-password", "file": "encrypted-user-password.pdf", "covers": ["FR-02"],
     "password": "wrong", "expectError": "wrongPassword"},
    {"id": "copy-restricted", "file": "copy-restricted.pdf", "covers": ["FR-03"],
     "expectError": "copyingNotPermitted"},
    {"id": "copy-restricted-owner", "file": "copy-restricted.pdf", "covers": ["FR-03"],
     "password": "owner-only", "ownerPasswordCase": True,
     "mustContain": ["The author disallowed text copying for this document."], "ocrPages": []},
    {
        "id": "unicode-normalization",
        "reportExactly": CLEAN,
        "file": "unicode-normalization.pdf",
        "covers": ["FR-14", "FR-15"],
        "title": "Unicode Normalisation",
        "mustContain": ["The financial flow is reviewed monthly.",
                        "Größe und Übersicht der Straße bleiben erhalten.",
                        "L’élève a réussi l’examen.",
                        "Information with a soft hyphen.",
                        "Standalone marks survive : a \u2013 b . c _ d ( e ) f , g ; h \u00b7 i"],
        "mustNotContainCodepoints": ["FB01", "FB02", "00AD"],
        "ocrPages": [],
    },
    {"id": "not-a-pdf", "file": "not-a-pdf.pdf", "covers": ["FR-02"], "expectError": "notAPDF"},
    {"id": "truncated", "file": "truncated.pdf", "covers": ["NFR-06"], "expectNoCrash": True},
    {
        "id": "perf-200-pages",
        "reportExactly": CLEAN,
        "file": "perf-200-pages.pdf",
        "covers": ["NFR-03"],
        "mustContain": ["Chapter 1", "Chapter 200"],
        "headingCount": 200,
        "ocrPages": [],
        "maxSeconds": 20,
    },
]

OUT.write_text(json.dumps({"version": 1, "fixtures": fixtures}, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"wrote {OUT} ({len(fixtures)} cases)")
