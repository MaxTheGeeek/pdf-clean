import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U08 (T-013).
@Suite("MarkdownRenderer")
struct MarkdownRendererTests {
    @Test("golden: every block type, with escaping")
    func goldenEveryBlockType() {
        let document = goldenDocument()
        let expected = """
            # Quarterly \\*Report\\*

            ## Intro & Scope

            This covers Q3 \\<2026\\> results & outlook.

            - First bullet
              - Nested bullet

            1. First step
            2. Second step

            ## Contents
            - Intro (p. 1)
              - Scope (p. 1)

            ```
            code <line>
            second line
            ```

            ---

            ### Appendix
            """
        #expect(MarkdownRenderer.render(document) == expected + "\n")
    }

    @Test("heading hash count has no title to compensate for")
    func headingWithoutTitle() {
        let document = ExtractedDocument(
            blocks: [.heading(level: 1, text: "Top"), .heading(level: 2, text: "Sub")],
            report: SanitizationReport(),
            pageCount: 1
        )
        #expect(MarkdownRenderer.render(document) == "# Top\n\n## Sub\n")
    }

    @Test("heading level is capped at 6 hashes")
    func headingCappedAtSix() {
        let document = ExtractedDocument(
            blocks: [.title("T"), .heading(level: 10, text: "Deep")],
            report: SanitizationReport(),
            pageCount: 1
        )
        #expect(MarkdownRenderer.render(document) == "# T\n\n###### Deep\n")
    }

    @Test("math regions stay distinct from ordinary paragraphs")
    func rendersInlineAndDisplayMathBlocks() {
        let document = ExtractedDocument(
            blocks: [
                .paragraph("A quick check."),
                .math(MathBlock(text: "E = mc^2", kind: .inline)),
                .math(MathBlock(text: "a^2 + b^2 = c^2", kind: .display)),
            ],
            report: SanitizationReport(),
            pageCount: 1
        )
        #expect(
                MarkdownRenderer.render(document) ==
                    "A quick check. $E = mc^2$\n\n$$\na^2 + b^2 = c^2\n$$\n"
        )
    }

    @Test(
        "characters are escaped anywhere in text",
        arguments: [
            ("a\\b", "a\\\\b"),
            ("a`b", "a\\`b"),
            ("a*b", "a\\*b"),
            ("a_b", "a\\_b"),
            ("a[b]c", "a\\[b\\]c"),
            ("a<b>c", "a\\<b\\>c"),
            ("a|b", "a\\|b"),
        ]
    )
    func characterEscaping(_ pair: (input: String, expected: String)) {
        #expect(MarkdownRenderer.escape(pair.input) == pair.expected)
    }

    @Test(
        "a line starting with #, +, -, =, > or N.) gets a leading backslash",
        arguments: ["#heading", "+bullet", "-bullet", "=equals", ">quote", "1.ordered", "2)ordered"]
    )
    func lineStartEscaping(_ line: String) {
        #expect(MarkdownRenderer.escape(line) == "\\" + line)
    }

    @Test("a plain line is not escaped")
    func plainLineUnescaped() {
        #expect(MarkdownRenderer.escape("Plain sentence.") == "Plain sentence.")
    }

    func goldenDocument() -> ExtractedDocument {
        ExtractedDocument(
            blocks: [
                .title("Quarterly *Report*"),
                .heading(level: 1, text: "Intro & Scope"),
                .paragraph("This covers Q3 <2026> results & outlook."),
                .listItem(ListItem(ordered: false, marker: "-", level: 0, text: "First bullet")),
                .listItem(ListItem(ordered: false, marker: "-", level: 1, text: "Nested bullet")),
                .listItem(ListItem(ordered: true, marker: "1.", level: 0, text: "First step")),
                .listItem(ListItem(ordered: true, marker: "2.", level: 0, text: "Second step")),
                .tableOfContents(
                    heading: "Contents",
                    entries: [
                        TOCEntry(level: 1, title: "Intro", page: "1"),
                        TOCEntry(level: 2, title: "Scope", page: "1"),
                    ]
                ),
                .preformatted("code <line>\nsecond line"),
                .pageBreak(page: 2),
                .heading(level: 2, text: "Appendix"),
            ],
            report: SanitizationReport(),
            pageCount: 2,
            dominantLanguage: "en-US"
        )
    }
}
