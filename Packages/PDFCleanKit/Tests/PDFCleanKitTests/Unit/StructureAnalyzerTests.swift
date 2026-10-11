import CoreGraphics
import Foundation
import Testing

@testable import PDFCleanKit

/// T-024 "Done when": a synthetic multi-page document yields the expected `[Block]` sequence —
/// confirms `StructureAnalyzer` wires title/heading/list/paragraph detection together in the
/// right order, and that a detected TOC is placed after the title and its entries act as
/// heading hints on later pages.
@Suite("StructureAnalyzer")
struct StructureAnalyzerTests {

    @Test("title, heading, paragraph and list items across two pages, in reading order")
    func fullDocument() {
        let lines = [
            textLine("Annual Report", page: 0, y: 0, size: 24, isBold: true),
            textLine("Introduction", page: 0, y: 40, size: 16),
            textLine("This report covers results.", page: 0, y: 80, size: 12),
            wordLine(page: 0, y: 100, words: [("•", 0, 10), ("First", 15, 30), ("point", 50, 35)]),
            wordLine(page: 0, y: 120, words: [("•", 0, 10), ("Second", 15, 40), ("point", 60, 35)]),
            textLine("Conclusion", page: 1, y: 0, size: 16),
            textLine("This wraps things up nicely.", page: 1, y: 40, size: 12),
        ]
        let blocks = StructureAnalyzer.analyze(lines: lines, pageHeights: [0: 400, 1: 400])

        #expect(
            blocks == [
                .title("Annual Report"),
                .heading(level: 1, text: "Introduction"),
                .paragraph("This report covers results."),
                .listItem(ListItem(ordered: false, marker: "•", level: 0, text: "First point")),
                .listItem(ListItem(ordered: false, marker: "•", level: 0, text: "Second point")),
                .heading(level: 1, text: "Conclusion"),
                .paragraph("This wraps things up nicely."),
            ])
    }

    @Test("the detected TOC sits after the title, and its entry becomes a heading hint later on")
    func tocPlacementAndHeadingHint() {
        let lines = [
            textLine("Guide", page: 0, y: 0, size: 24, isBold: true),
            textLine("Contents", page: 0, y: 40, size: 12),
            textLine("Setup.....1", page: 0, y: 60, size: 12),
            // Page 1: plain, non-bold, body-sized text that typography alone would never flag —
            // only the TOC-derived hint makes "Setup" a heading here.
            textLine("Setup", page: 1, y: 0, size: 12),
            textLine("Setup details follow here right away.", page: 1, y: 20, size: 12),
        ]
        let blocks = StructureAnalyzer.analyze(lines: lines, pageHeights: [0: 400, 1: 400])

        #expect(
            blocks == [
                .title("Guide"),
                .tableOfContents(heading: "Contents", entries: [TOCEntry(level: 1, title: "Setup", page: "1")]),
                .heading(level: 1, text: "Setup"),
                .paragraph("Setup details follow here right away."),
            ])
    }

    @Test("an empty document yields no blocks")
    func emptyDocument() {
        #expect(StructureAnalyzer.analyze(lines: []).isEmpty)
    }

    // MARK: - Fixtures

    func textLine(_ text: String, page: Int, y: CGFloat, size: CGFloat, isBold: Bool = false) -> Line {
        let box = CGRect(x: 0, y: y, width: CGFloat(text.count) * size * 0.5, height: size * 0.875)
        let word = Word(text: text, box: box, pageBox: .zero, glyphs: [], fontSize: size, isBold: isBold)
        return Line(page: page, words: [word], box: box, fontSize: size, isBold: isBold, source: .textLayer)
    }

    func wordLine(page: Int, y: CGFloat, size: CGFloat = 12, words: [(String, CGFloat, CGFloat)]) -> Line {
        let built = words.map { text, x, width in
            Word(
                text: text, box: CGRect(x: x, y: y, width: width, height: 14), pageBox: .zero, glyphs: [],
                fontSize: size, isBold: false)
        }
        let box = built.reduce(CGRect.null) { $0.union($1.box) }
        return Line(page: page, words: built, box: box, fontSize: size, isBold: false, source: .textLayer)
    }
}
