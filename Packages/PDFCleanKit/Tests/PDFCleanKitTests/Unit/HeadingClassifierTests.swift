import CoreGraphics
import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U20 (T-022): `HeadingClassifier` — title detection (incl. the recurring-style guard),
/// heading levels by size rank, the bold-at-body-size level, the numbering tie-break, and
/// adjacent-line merging for both title and headings.
@Suite("HeadingClassifier")
struct HeadingClassifierTests {

    @Test("normalize casefolds, collapses whitespace and strips trailing dots/numbers")
    func normalize() {
        #expect(HeadingClassifier.normalize("  Introduction   To   Swift  ") == "introduction to swift")
        #expect(HeadingClassifier.normalize("Chapter One...") == "chapter one")
        #expect(HeadingClassifier.normalize("Scope 2.1") == "scope")
    }

    @Test("distinct heading sizes rank into levels 1, 2, 3 descending")
    func sizeLevels() {
        // Sizes stay below the title threshold (1.4 x body = 11.2) so none of them is mistaken
        // for the document title — only the heading threshold (1.15 x body = 9.2) matters here.
        let lines = [
            line("Big Heading", x: 0, y: 0, size: 11, page: 1),
            line("Normal text here.", x: 0, y: 40, size: 8, page: 1),
            line("Medium Heading", x: 0, y: 80, size: 10, page: 1),
            line("More normal text.", x: 0, y: 120, size: 8, page: 1),
            line("Small Heading", x: 0, y: 160, size: 9.5, page: 1),
        ]
        let result = HeadingClassifier.classify(lines: lines, pageHeights: [:], bodySize: 8, bodySpacing: 16)
        #expect(
            result == [
                .heading(level: 1, text: "Big Heading"),
                .body(lines[1]),
                .heading(level: 2, text: "Medium Heading"),
                .body(lines[3]),
                .heading(level: 3, text: "Small Heading"),
            ])
    }

    @Test("a bold line at body size sits one level below the smallest real heading level")
    func boldAtBodySizeLevel() {
        let lines = [
            line("Section Heading", x: 0, y: 0, size: 16, page: 1),  // real heading, level 1
            line("Body text goes here.", x: 0, y: 40, size: 12, page: 1),
            line("Bold Note", x: 0, y: 100, size: 12, isBold: true, page: 1),  // gap 46 >= 1.2x20
        ]
        let result = HeadingClassifier.classify(lines: lines, pageHeights: [:], bodySize: 12, bodySpacing: 20)
        #expect(
            result == [
                .heading(level: 1, text: "Section Heading"),
                .body(lines[1]),
                .heading(level: 2, text: "Bold Note"),
            ])
    }

    @Test("a bold-at-body line with no other heading level falls back to level 1")
    func boldAtBodySizeWithNoRealHeadings() {
        let lines = [
            line("Body text goes here.", x: 0, y: 0, size: 12, page: 1),
            line("Bold Note", x: 0, y: 60, size: 12, isBold: true, page: 1),  // gap 46 >= 24
        ]
        let result = HeadingClassifier.classify(lines: lines, pageHeights: [:], bodySize: 12, bodySpacing: 20)
        #expect(result == [.body(lines[0]), .heading(level: 1, text: "Bold Note")])
    }

    @Test("numbering depth breaks a tie between two headings that share one font size")
    func numberingTieBreak() {
        let lines = [
            line("1 Introduction", x: 0, y: 0, size: 16, page: 1),
            line("Body filler paragraph text.", x: 0, y: 40, size: 12, page: 1),
            line("1.1 Scope", x: 0, y: 100, size: 16, page: 1),  // same size as above, deeper number
        ]
        let result = HeadingClassifier.classify(lines: lines, pageHeights: [:], bodySize: 12, bodySpacing: 20)
        #expect(
            result == [
                .heading(level: 1, text: "1 Introduction"),
                .body(lines[1]),
                .heading(level: 2, text: "1.1 Scope"),
            ])
    }

    @Test("adjacent lines with the same style merge into one title")
    func titleMerge() {
        let lines = [
            line("Annual", x: 0, y: 0, size: 24, isBold: true, page: 0),
            line("Report", x: 0, y: 28, size: 24, isBold: true, page: 0),
            line("Body text starts the document here.", x: 0, y: 60, size: 12, page: 0),
        ]
        let result = HeadingClassifier.classify(
            lines: lines, pageHeights: [0: 400], bodySize: 12, bodySpacing: 20)
        #expect(result == [.title("Annual Report"), .body(lines[2])])
    }

    @Test("adjacent heading candidates merge within the gap threshold, not beyond it")
    func headingMergeThreshold() {
        // bodySpacing 20, headingMergeGapFactor 1.3 -> merge threshold 26.
        let merged = [
            line("Wrapped", x: 0, y: 0, size: 16, page: 1),
            line("Heading", x: 0, y: 20, size: 16, page: 1),  // gap 6 (box maxY 14 -> 20-14=6) <= 26
        ]
        let mergedResult = HeadingClassifier.classify(
            lines: merged, pageHeights: [:], bodySize: 12, bodySpacing: 20)
        #expect(mergedResult == [.heading(level: 1, text: "Wrapped Heading")])

        let separate = [
            line("First Heading", x: 0, y: 0, size: 16, page: 1),
            line("Second Heading", x: 0, y: 60, size: 16, page: 1),  // gap 46 > 26: two headings
        ]
        let separateResult = HeadingClassifier.classify(
            lines: separate, pageHeights: [:], bodySize: 12, bodySpacing: 20)
        #expect(
            separateResult == [
                .heading(level: 1, text: "First Heading"),
                .heading(level: 1, text: "Second Heading"),
            ])
    }

    @Test("a style that recurs on more than one other page is not a title")
    func recurringStyleIsNotATitle() {
        let lines = [
            line("Chapter 1", x: 0, y: 0, size: 18, isBold: true, page: 0),
            line("Chapter 2", x: 0, y: 0, size: 18, isBold: true, page: 1),
            line("Chapter 3", x: 0, y: 0, size: 18, isBold: true, page: 2),
        ]
        let result = HeadingClassifier.classify(
            lines: lines, pageHeights: [0: 400, 1: 400, 2: 400], bodySize: 10, bodySpacing: 16)
        #expect(!result.contains { if case .title = $0 { return true } else { return false } })
        #expect(result.first == .heading(level: 1, text: "Chapter 1"))
    }

    @Test("a style that recurs on at most one other page is still accepted as a title")
    func nonRecurringStyleIsATitle() {
        let lines = [
            line("One-off Title", x: 0, y: 0, size: 18, isBold: true, page: 0),
            line("Same style, once", x: 0, y: 0, size: 18, isBold: true, page: 1),
        ]
        let result = HeadingClassifier.classify(
            lines: lines, pageHeights: [0: 400, 1: 400], bodySize: 10, bodySpacing: 16)
        #expect(result.first == .title("One-off Title"))
    }

    @Test("an outline/TOC hint takes priority over typographic detection")
    func hintTakesPriority() {
        // "Preface" is plain body-sized, non-bold text: typography alone would never flag it.
        let lines = [line("Preface", x: 0, y: 0, size: 12, page: 3)]
        let hints = [HeadingClassifier.Hint(page: 3, normalizedText: "preface", level: 2)]
        let result = HeadingClassifier.classify(
            lines: lines, pageHeights: [:], bodySize: 12, bodySpacing: 20, hints: hints)
        #expect(result == [.heading(level: 2, text: "Preface")])
    }

    @Test("empty input yields no classifications")
    func emptyInput() {
        #expect(HeadingClassifier.classify(lines: [], pageHeights: [:], bodySize: 12, bodySpacing: 20).isEmpty)
    }

    // MARK: - Fixtures

    func line(
        _ text: String, x: CGFloat, y: CGFloat, size: CGFloat, isBold: Bool = false, page: Int
    ) -> Line {
        let box = CGRect(x: x, y: y, width: CGFloat(text.count) * size * 0.5, height: size * 0.875)
        let word = Word(text: text, box: box, pageBox: .zero, glyphs: [], fontSize: size, isBold: isBold)
        return Line(page: page, words: [word], box: box, fontSize: size, isBold: isBold, source: .textLayer)
    }
}
