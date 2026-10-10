import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U09 (T-013).
@Suite("HTMLRenderer")
struct HTMLRendererTests {
    @Test("skeleton matches the spec exactly, with lang from dominant language")
    func skeletonExact() {
        let document = ExtractedDocument(
            blocks: [.title("My Title"), .paragraph("Body.")],
            report: SanitizationReport(),
            pageCount: 1,
            dominantLanguage: "de-DE"
        )
        let html = HTMLRenderer.render(document)
        let expectedPrefix = """
            <!doctype html><html lang="de-DE"><head>\
            <meta charset="utf-8">\
            <meta name="viewport" content="width=device-width, initial-scale=1">\
            <title>My Title</title>\
            <style>\(PrintCSS.css)</style>\
            </head><body><main>
            """
        #expect(html.hasPrefix(expectedPrefix))
        #expect(html.hasSuffix("</main></body></html>\n"))
        #expect(html.contains("<h1>My Title</h1>"))
        #expect(html.contains("<p>Body.</p>"))
    }

    @Test("lang falls back to und, title falls back to Document")
    func fallbacks() {
        let document = ExtractedDocument(
            blocks: [.paragraph("No title here.")],
            report: SanitizationReport(),
            pageCount: 1
        )
        let html = HTMLRenderer.render(document)
        #expect(html.contains("<html lang=\"und\">"))
        #expect(html.contains("<title>Document</title>"))
    }

    @Test("only charset and viewport meta tags, no script/link/img")
    func onlyAllowedMetaAndNoDisallowedTags() {
        let document = ExtractedDocument(
            blocks: [.title("T")],
            report: SanitizationReport(),
            pageCount: 1
        )
        let html = HTMLRenderer.render(document)
        let metaCount = html.components(separatedBy: "<meta ").count - 1
        #expect(metaCount == 2)
        #expect(!html.contains("<script"))
        #expect(!html.contains("<link"))
        #expect(!html.contains("<img"))
    }

    @Test("escapes & < > \" ' in text content")
    func escapesSpecialCharacters() {
        let document = ExtractedDocument(
            blocks: [.paragraph("A & B < C > D \" E ' F")],
            report: SanitizationReport(),
            pageCount: 1
        )
        let html = HTMLRenderer.render(document)
        #expect(html.contains("<p>A &amp; B &lt; C &gt; D &quot; E &#39; F</p>"))
    }

    @Test("nested lists open and close correctly across an ordered/unordered switch")
    func nestedListsAndOrderedSwitch() {
        let document = ExtractedDocument(
            blocks: [
                .listItem(ListItem(ordered: false, marker: "-", level: 0, text: "One")),
                .listItem(ListItem(ordered: false, marker: "-", level: 1, text: "Two")),
                .listItem(ListItem(ordered: true, marker: "1.", level: 0, text: "Alpha")),
                .listItem(ListItem(ordered: true, marker: "2.", level: 0, text: "Beta")),
            ],
            report: SanitizationReport(),
            pageCount: 1
        )
        let html = HTMLRenderer.render(document)
        let expectedList =
            "<ul><li>One<ul><li>Two</li></ul></li></ul>"
            + "<ol><li>Alpha</li><li>Beta</li></ol>"
        #expect(html.contains(expectedList))
    }

    @Test("table of contents renders as nav > h2 + nested ol")
    func tableOfContentsStructure() {
        let document = ExtractedDocument(
            blocks: [
                .tableOfContents(
                    heading: "Contents",
                    entries: [
                        TOCEntry(level: 1, title: "Intro", page: "1"),
                        TOCEntry(level: 2, title: "Scope", page: "1"),
                    ]
                )
            ],
            report: SanitizationReport(),
            pageCount: 1
        )
        let html = HTMLRenderer.render(document)
        let expectedTOC =
            "<nav><h2>Contents</h2><ol><li>Intro (p. 1)<ol><li>Scope (p. 1)</li></ol></li></ol></nav>"
        #expect(html.contains(expectedTOC))
    }

    @Test("preformatted text is escaped inside <pre>, page break is <hr>")
    func preformattedAndPageBreak() {
        let document = ExtractedDocument(
            blocks: [.preformatted("a < b"), .pageBreak(page: 2)],
            report: SanitizationReport(),
            pageCount: 2
        )
        let html = HTMLRenderer.render(document)
        #expect(html.contains("<pre>a &lt; b</pre>"))
        #expect(html.contains("<hr>"))
    }
}
