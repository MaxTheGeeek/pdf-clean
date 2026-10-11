import CoreGraphics
import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U21 (T-023): `TOCDetector` — dot leaders, space leaders, roman page numbers, wrapped
/// entries, the "Inhaltsverzeichnis" keyword, continuation pages, indentation/numbering levels,
/// and rejecting a non-TOC page that merely has trailing numbers.
@Suite("TOCDetector")
struct TOCDetectorTests {

    @Test("dot leaders, space leaders, roman numerals and a wrapped entry, under a Contents heading")
    func mixedLeadersAndWrappedEntry() {
        let lines = [
            line("Contents", x: 0, y: 0, page: 0),
            line("Introduction.....1", x: 0, y: 20, page: 0),
            line("Background and", x: 0, y: 40, page: 0),  // wrapped: no page number yet
            line("Motivation....3", x: 0, y: 60, page: 0),  // completes the wrapped entry
            line("Appendix     ii", x: 0, y: 80, page: 0),  // space leaders, roman numeral
        ]
        let result = TOCDetector.detect(lines: lines)
        #expect(result?.heading == "Contents")
        #expect(
            result?.entries == [
                TOCEntry(level: 1, title: "Introduction", page: "1"),
                TOCEntry(level: 1, title: "Background and Motivation", page: "3"),
                TOCEntry(level: 1, title: "Appendix", page: "ii"),
            ])
        #expect(result?.consumedIndices == Set(0...4))
    }

    @Test("Inhaltsverzeichnis is recognised as the TOC heading keyword")
    func germanKeyword() {
        let lines = [
            line("Inhaltsverzeichnis", x: 0, y: 0, page: 0),
            line("Einleitung.....1", x: 0, y: 20, page: 0),
            line("Ende.....9", x: 0, y: 40, page: 0),
        ]
        let result = TOCDetector.detect(lines: lines)
        #expect(result?.heading == "Inhaltsverzeichnis")
        #expect(result?.entries.count == 2)
    }

    @Test("a continuation page with no heading of its own still joins the run via the line ratio")
    func continuationPage() {
        let lines = [
            line("Contents", x: 0, y: 0, page: 0),
            line("One.....1", x: 0, y: 20, page: 0),
            line("Two.....2", x: 0, y: 40, page: 0),
            line("Three.....3", x: 0, y: 60, page: 0),
            // Page 1: no keyword, but 4/4 lines match the entry pattern (ratio 1.0 >= 0.4).
            line("Four.....4", x: 0, y: 0, page: 1),
            line("Five.....5", x: 0, y: 20, page: 1),
            line("Six.....6", x: 0, y: 40, page: 1),
            line("Seven.....7", x: 0, y: 60, page: 1),
        ]
        let result = TOCDetector.detect(lines: lines)
        #expect(result?.entries.map(\.title) == ["One", "Two", "Three", "Four", "Five", "Six", "Seven"])
    }

    @Test("a non-TOC page with ordinary trailing numbers is not detected as a TOC page")
    func nonTOCPageRejected() {
        let lines = [
            line("Revenue grew in Q1 2026", x: 0, y: 0, page: 0),
            line("Costs were steady in 2025", x: 0, y: 20, page: 0),
            line("Forecasts assume growth of 10", x: 0, y: 40, page: 0),
            line("Margins held near 20", x: 0, y: 60, page: 0),
            line("Headcount reached 200", x: 0, y: 80, page: 0),
        ]
        #expect(TOCDetector.detect(lines: lines) == nil)
    }

    @Test("indentation clusters assign nested entry levels")
    func indentationLevels() {
        let lines = [
            line("Contents", x: 0, y: 0, page: 0),
            line("Chapter One.....1", x: 0, y: 20, page: 0),
            line("Scope.....2", x: 20, y: 40, page: 0),
            line("Method.....3", x: 20, y: 60, page: 0),
            line("Chapter Two.....5", x: 0, y: 80, page: 0),
        ]
        let result = TOCDetector.detect(lines: lines)
        #expect(
            result?.entries == [
                TOCEntry(level: 1, title: "Chapter One", page: "1"),
                TOCEntry(level: 2, title: "Scope", page: "2"),
                TOCEntry(level: 2, title: "Method", page: "3"),
                TOCEntry(level: 1, title: "Chapter Two", page: "5"),
            ])
    }

    @Test("numbering in the entry title overrides indentation for the level")
    func numberingOverridesIndentation() {
        // Both entries sit at the same indentation; without numbering they would tie at level 1.
        let lines = [
            line("Contents", x: 0, y: 0, page: 0),
            line("1 Introduction.....1", x: 0, y: 20, page: 0),
            line("1.1 Scope.....2", x: 0, y: 40, page: 0),
        ]
        let result = TOCDetector.detect(lines: lines)
        #expect(
            result?.entries == [
                TOCEntry(level: 1, title: "1 Introduction", page: "1"),
                TOCEntry(level: 2, title: "1.1 Scope", page: "2"),
            ])
    }

    @Test("no TOC anywhere in the document yields nil")
    func noTOCAtAll() {
        let lines = [
            line("Just a normal paragraph of text.", x: 0, y: 0, page: 0),
            line("Another normal paragraph follows.", x: 0, y: 20, page: 0),
        ]
        #expect(TOCDetector.detect(lines: lines) == nil)
    }

    // MARK: - Fixtures

    func line(_ text: String, x: CGFloat, y: CGFloat, page: Int) -> Line {
        let box = CGRect(x: x, y: y, width: CGFloat(text.count) * 6, height: 14)
        let word = Word(text: text, box: box, pageBox: .zero, glyphs: [], fontSize: 12, isBold: false)
        return Line(page: page, words: [word], box: box, fontSize: 12, isBold: false, source: .textLayer)
    }
}
