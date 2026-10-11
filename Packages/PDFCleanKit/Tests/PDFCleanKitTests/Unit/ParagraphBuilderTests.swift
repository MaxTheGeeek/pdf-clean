import CoreGraphics
import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U23 (T-024): `ParagraphBuilder` — the gap rule, the indent rule, the short-line rule, the
/// hyphen join (lowercase / uppercase / digit), the soft-hyphen join, cross-page continuation,
/// and preformatted (table-like) run detection.
@Suite("ParagraphBuilder")
struct ParagraphBuilderTests {

    @Test("a gap above wider than 1.4 x body spacing starts a new paragraph")
    func gapRule() {
        let lines = [
            line("First paragraph line.", x: 0, y: 0, page: 0),
            line("Still first paragraph.", x: 0, y: 14, page: 0),  // gap 0 (box height 14): same paragraph
            line("Second paragraph starts here.", x: 0, y: 60, page: 0),  // gap 32 > 1.4x20=28
        ]
        let blocks = ParagraphBuilder.build(lines: lines, bodySpacing: 20)
        #expect(
            blocks == [
                .paragraph("First paragraph line. Still first paragraph."),
                .paragraph("Second paragraph starts here."),
            ])
    }

    @Test("a first-line indent beyond 1 em from the column's left edge starts a new paragraph")
    func indentRule() {
        let lines = [
            line("Body text at the left edge.", x: 0, y: 0, page: 0),
            line("Indented new paragraph begins.", x: 20, y: 14, page: 0),  // 20pt > 1em (12pt)
        ]
        let blocks = ParagraphBuilder.build(lines: lines, bodySpacing: 20)
        #expect(
            blocks == [
                .paragraph("Body text at the left edge."),
                .paragraph("Indented new paragraph begins."),
            ])
    }

    @Test("a short line ending in terminal punctuation ends its paragraph")
    func shortLineRule() {
        let lines = [
            line("This is a long full-width line that fills the column.", x: 0, y: 0, page: 0, width: 300),
            line("Short end.", x: 0, y: 14, page: 0, width: 60),  // < 0.7 x 300 and ends with '.'
            line("A brand new paragraph follows.", x: 0, y: 28, page: 0, width: 300),
        ]
        let blocks = ParagraphBuilder.build(lines: lines, bodySpacing: 20)
        #expect(
            blocks == [
                .paragraph("This is a long full-width line that fills the column. Short end."),
                .paragraph("A brand new paragraph follows."),
            ])
    }

    @Test("a font size or weight change starts a new paragraph")
    func styleChangeRule() {
        let lines = [
            line("Normal body text here.", x: 0, y: 0, page: 0),
            line("Suddenly bold text.", x: 0, y: 14, page: 0, isBold: true),
        ]
        let blocks = ParagraphBuilder.build(lines: lines, bodySpacing: 20)
        #expect(blocks == [.paragraph("Normal body text here."), .paragraph("Suddenly bold text.")])
    }

    @Test("a trailing hyphen before a lowercase start is removed and the words joined")
    func hyphenJoinLowercase() {
        let lines = [
            line("This word is infra-", x: 0, y: 0, page: 0),
            line("structure.", x: 0, y: 14, page: 0),
        ]
        let blocks = ParagraphBuilder.build(lines: lines, bodySpacing: 20)
        #expect(blocks == [.paragraph("This word is infrastructure.")])
    }

    @Test("a trailing soft hyphen before a lowercase start behaves like a visible hyphen")
    func softHyphenJoinLowercase() {
        let lines = [
            line("This word is infra\u{00AD}", x: 0, y: 0, page: 0),
            line("structure.", x: 0, y: 14, page: 0),
        ]
        let blocks = ParagraphBuilder.build(lines: lines, bodySpacing: 20)
        #expect(blocks == [.paragraph("This word is infrastructure.")])
    }

    @Test("a trailing hyphen before an uppercase or digit start is kept, joined with no space")
    func hyphenJoinUppercaseOrDigit() {
        let uppercase = ParagraphBuilder.build(
            lines: [line("See Appendix-", x: 0, y: 0, page: 0), line("B for details.", x: 0, y: 14, page: 0)],
            bodySpacing: 20)
        #expect(uppercase == [.paragraph("See Appendix-B for details.")])

        let digit = ParagraphBuilder.build(
            lines: [line("Model T-", x: 0, y: 0, page: 0), line("1000 shipped.", x: 0, y: 14, page: 0)],
            bodySpacing: 20)
        #expect(digit == [.paragraph("Model T-1000 shipped.")])
    }

    @Test("a hyphen not preceded by a letter falls back to a plain space join")
    func hyphenNotPrecededByLetter() {
        let blocks = ParagraphBuilder.build(
            lines: [line("Totals: 5-", x: 0, y: 0, page: 0), line("10 items.", x: 0, y: 14, page: 0)],
            bodySpacing: 20)
        #expect(blocks == [.paragraph("Totals: 5- 10 items.")])
    }

    @Test("a paragraph continues across a page break when unpunctuated and the next starts lowercase")
    func crossPageContinuation() {
        let lines = [
            line("The sentence runs onto the next", x: 0, y: 0, page: 0),
            line("page without a full stop.", x: 0, y: 0, page: 1),
        ]
        let blocks = ParagraphBuilder.build(lines: lines, bodySpacing: 20)
        #expect(blocks == [.paragraph("The sentence runs onto the next page without a full stop.")])
    }

    @Test("a paragraph does not continue across a page break when the previous line is punctuated")
    func noCrossPageContinuationWhenPunctuated() {
        let lines = [
            line("This sentence is complete.", x: 0, y: 0, page: 0),
            line("A new one starts on the next page.", x: 0, y: 0, page: 1),
        ]
        let blocks = ParagraphBuilder.build(lines: lines, bodySpacing: 20)
        #expect(
            blocks == [.paragraph("This sentence is complete."), .paragraph("A new one starts on the next page.")])
    }

    @Test(
        "a page break is inserted at a non-continued page transition when includePageBreaks is on"
    )
    func pageBreakInserted() {
        let lines = [
            line("This sentence is complete.", x: 0, y: 0, page: 0),
            line("A new one starts on the next page.", x: 0, y: 0, page: 1),
        ]
        let blocks = ParagraphBuilder.build(lines: lines, bodySpacing: 20, includePageBreaks: true)
        #expect(
            blocks == [
                .paragraph("This sentence is complete."),
                .pageBreak(page: 1),
                .paragraph("A new one starts on the next page."),
            ])
    }

    @Test("three or more consecutive table-like lines become one preformatted block")
    func preformattedRun() {
        let lines = [
            line("Intro paragraph before the table.", x: 0, y: 0, page: 0),
            tableLine(["Name", "Qty", "Price"], y: 30, page: 0),
            tableLine(["Widget", "4", "9.99"], y: 50, page: 0),
            tableLine(["Gadget", "2", "19.99"], y: 70, page: 0),
            line("Closing paragraph after the table.", x: 0, y: 100, page: 0),
        ]
        let blocks = ParagraphBuilder.build(lines: lines, bodySpacing: 20)
        #expect(
            blocks == [
                .paragraph("Intro paragraph before the table."),
                .preformatted("Name  Qty  Price\nWidget  4  9.99\nGadget  2  19.99"),
                .paragraph("Closing paragraph after the table."),
            ])
    }

    @Test("fewer than 3 table-like lines do not become preformatted")
    func shortTableLikeRunStaysParagraphs() {
        let lines = [
            tableLine(["Name", "Qty", "Price"], y: 0, page: 0),
            tableLine(["Widget", "4", "9.99"], y: 20, page: 0),
        ]
        let blocks = ParagraphBuilder.build(lines: lines, bodySpacing: 20)
        if case .preformatted = blocks.first {
            Issue.record("expected no preformatted block for only 2 table-like lines")
        }
    }

    // MARK: - Fixtures

    func line(
        _ text: String, x: CGFloat, y: CGFloat, page: Int, width: CGFloat = 200, size: CGFloat = 12,
        isBold: Bool = false
    ) -> Line {
        let box = CGRect(x: x, y: y, width: width, height: 14)
        let word = Word(text: text, box: box, pageBox: .zero, glyphs: [], fontSize: size, isBold: isBold)
        return Line(page: page, words: [word], box: box, fontSize: size, isBold: isBold, source: .textLayer)
    }

    /// A line of several short words spaced far apart (table-like: gaps well over 2 x size).
    func tableLine(_ cells: [String], y: CGFloat, page: Int, size: CGFloat = 12) -> Line {
        var words: [Word] = []
        var x: CGFloat = 0
        for cell in cells {
            let width = CGFloat(cell.count) * 6
            words.append(
                Word(
                    text: cell, box: CGRect(x: x, y: y, width: width, height: 14), pageBox: .zero, glyphs: [],
                    fontSize: size, isBold: false))
            x += width + 40  // gap of 40pt, well over 2 x 12 = 24
        }
        let box = words.reduce(CGRect.null) { $0.union($1.box) }
        return Line(page: page, words: words, box: box, fontSize: size, isBold: false, source: .textLayer)
    }
}
