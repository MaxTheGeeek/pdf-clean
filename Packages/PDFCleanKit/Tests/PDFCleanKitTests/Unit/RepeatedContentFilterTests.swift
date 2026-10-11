import CoreGraphics
import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U17 (T-025): `RepeatedContentFilter` — Rule A with digit normalisation, the size cap that
/// protects large recurring text (e.g. "Chapter N" headings) from Rule A, Rule B by exact text
/// and position, Rule C page-number patterns (EN/DE/roman/dash), rule precedence (A before C,
/// so a line counted by A is not counted again by C), and the single-page no-op.
@Suite("RepeatedContentFilter")
struct RepeatedContentFilterTests {

    let pageSizes: [Int: CGSize] = [
        0: .init(width: 800, height: 1000), 1: .init(width: 800, height: 1000),
        2: .init(width: 800, height: 1000), 3: .init(width: 800, height: 1000),
    ]

    @Test("Rule A removes a footer whose digit-normalised key repeats across pages")
    func ruleADigitNormalization() {
        let lines = (1...4).map { page in
            makeLine("ACME Corp - Page \(page)", page: page - 1, x: 0, y: 950)
        }
        let result = RepeatedContentFilter.filter(lines: lines, pageCount: 4, pageSizes: pageSizes, bodySize: 12)
        #expect(result.lines.isEmpty)
        #expect(result.removedHeaderFooterLines == 4)
        #expect(result.removedRepeatedLines == 0)
    }

    @Test("the size cap protects large recurring text (e.g. Chapter N headings) from Rule A")
    func sizeCapProtectsHeadings() {
        let lines = (1...4).map { page in
            makeLine("Chapter \(page)", page: page - 1, x: 0, y: 950, size: 16)  // 16 > 1.05 x 12
        }
        let result = RepeatedContentFilter.filter(lines: lines, pageCount: 4, pageSizes: pageSizes, bodySize: 12)
        #expect(result.lines.count == 4)
        #expect(result.removedHeaderFooterLines == 0)
    }

    @Test("Rule B removes identical text at the same relative position across pages")
    func ruleBExactTextAndPosition() {
        let lines = (0..<4).map { page in makeLine("CONFIDENTIAL", page: page, x: 300, y: 500, size: 10) }
        let result = RepeatedContentFilter.filter(lines: lines, pageCount: 4, pageSizes: pageSizes, bodySize: 12)
        #expect(result.lines.isEmpty)
        #expect(result.removedRepeatedLines == 4)
        #expect(result.removedHeaderFooterLines == 0)
    }

    @Test("Rule C removes non-repeating page-number lines in English, German, roman and dash styles")
    func ruleCPageNumberPatterns() {
        let lines = [
            makeLine("Page 3", page: 0, x: 0, y: 950),
            makeLine("Seite 4", page: 1, x: 0, y: 950),
            makeLine("iv", page: 2, x: 0, y: 950),
            makeLine("- 5 -", page: 3, x: 0, y: 950),
        ]
        let result = RepeatedContentFilter.filter(lines: lines, pageCount: 4, pageSizes: pageSizes, bodySize: 12)
        #expect(result.lines.isEmpty)
        #expect(result.removedHeaderFooterLines == 4)
    }

    @Test("a line caught by Rule A is not counted again by Rule C")
    func ruleOrderingAvoidsDoubleCounting() {
        // Bare "Page N" qualifies for both Rule A (digit-normalised "page #" repeats) and
        // Rule C's page-number pattern; it must be counted exactly once.
        let lines = (1...4).map { page in makeLine("Page \(page)", page: page - 1, x: 0, y: 950) }
        let result = RepeatedContentFilter.filter(lines: lines, pageCount: 4, pageSizes: pageSizes, bodySize: 12)
        #expect(result.lines.isEmpty)
        #expect(result.removedHeaderFooterLines == 4)
    }

    @Test("a single-page document is a no-op")
    func singlePageNoOp() {
        let lines = [makeLine("Page 1", page: 0, x: 0, y: 950)]
        let result = RepeatedContentFilter.filter(
            lines: lines, pageCount: 1, pageSizes: [0: CGSize(width: 800, height: 1000)], bodySize: 12)
        #expect(result.lines == lines)
        #expect(result.removedHeaderFooterLines == 0)
        #expect(result.removedRepeatedLines == 0)
    }

    @Test("options gate their rules: disabling removeHeadersFooters keeps Rule A/C matches")
    func optionsGateRules() {
        let lines = (1...4).map { page in makeLine("Page \(page)", page: page - 1, x: 0, y: 950) }
        let result = RepeatedContentFilter.filter(
            lines: lines, pageCount: 4, pageSizes: pageSizes, bodySize: 12, removeHeadersFooters: false)
        #expect(result.lines.count == 4)
        #expect(result.removedHeaderFooterLines == 0)
    }

    // MARK: - Fixtures

    func makeLine(_ text: String, page: Int, x: CGFloat, y: CGFloat, size: CGFloat = 12) -> Line {
        let box = CGRect(x: x, y: y, width: CGFloat(text.count) * size * 0.5, height: 14)
        let word = Word(text: text, box: box, pageBox: .zero, glyphs: [], fontSize: size, isBold: false)
        return Line(page: page, words: [word], box: box, fontSize: size, isBold: false, source: .textLayer)
    }
}
