import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U10 (T-013).
@Suite("PlainTextRenderer")
struct PlainTextRendererTests {
    @Test("golden: every block type")
    func goldenEveryBlockType() {
        let document = ExtractedDocument(
            blocks: [
                .title("Report"),
                .heading(level: 1, text: "Scope"),
                .paragraph("Body text here."),
                .listItem(ListItem(ordered: false, marker: "-", level: 0, text: "One")),
                .listItem(ListItem(ordered: false, marker: "-", level: 1, text: "Two")),
                .listItem(ListItem(ordered: true, marker: "1.", level: 0, text: "Alpha")),
                .listItem(ListItem(ordered: true, marker: "2.", level: 0, text: "Beta")),
                .tableOfContents(
                    heading: "Contents",
                    entries: [
                        TOCEntry(level: 1, title: "Intro", page: "1"),
                        TOCEntry(level: 2, title: "Scope", page: "1"),
                    ]
                ),
                .preformatted("line1\nline2"),
                .pageBreak(page: 2),
                .heading(level: 2, text: "Appendix"),
            ],
            report: SanitizationReport(),
            pageCount: 2
        )

        let expected = """
            Report
            ======

            Scope
            -----

            Body text here.

            \u{2022} One
              \u{2022} Two

            1. Alpha
            2. Beta

            Contents
            Intro 1
              Scope 1

            line1
            line2

            * * *

            Appendix
            """
        #expect(PlainTextRenderer.render(document) == expected + "\n")
    }

    @Test("sub-headings are not underlined, only level 1")
    func onlyLevelOneUnderlined() {
        let document = ExtractedDocument(
            blocks: [.heading(level: 1, text: "One"), .heading(level: 2, text: "Two")],
            report: SanitizationReport(),
            pageCount: 1
        )
        #expect(PlainTextRenderer.render(document) == "One\n---\n\nTwo\n")
    }

    @Test("no escaping of any kind")
    func noEscaping() {
        let document = ExtractedDocument(
            blocks: [.paragraph("a*b_c[d]e<f>g|h`i\\j")],
            report: SanitizationReport(),
            pageCount: 1
        )
        #expect(PlainTextRenderer.render(document) == "a*b_c[d]e<f>g|h`i\\j\n")
    }
}
