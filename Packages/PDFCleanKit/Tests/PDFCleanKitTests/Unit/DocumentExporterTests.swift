import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U07, TC-U12 (T-013).
@Suite("DocumentExporter")
struct DocumentExporterTests {
    private func documentWithIdentifier() -> ExtractedDocument {
        let needle = "3f2a9c1e-77b4-4c2e-9d1a-0b6e5f4a3c21"
        return ExtractedDocument(
            blocks: [
                .title("Title \(needle)"),
                .heading(level: 1, text: "Heading \(needle)"),
                .paragraph("Paragraph \(needle)."),
                .math(MathBlock(text: "E = mc^2 \(needle)", kind: .display)),
                .listItem(ListItem(ordered: false, marker: "-", level: 0, text: "Item \(needle)")),
                .tableOfContents(
                    heading: "Contents \(needle)",
                    entries: [TOCEntry(level: 1, title: "Entry \(needle)", page: "1")]
                ),
                .preformatted("Code \(needle)"),
            ],
            report: SanitizationReport(),
            pageCount: 1
        )
    }

    @Test("redaction replaces exact matches in every block type, in all three formats")
    func redactsEveryBlockTypeInAllFormats() throws {
        let needle = "3f2a9c1e-77b4-4c2e-9d1a-0b6e5f4a3c21"
        let document = documentWithIdentifier()
        let exporter = DocumentExporter()
        let options = ExportOptions(redactedIdentifiers: [needle])

        for format in ExportFormat.allCases {
            let rendered = try exporter.render(document, as: format, options: options)
            #expect(!rendered.contains(needle), "\(format) still contains the identifier")
            #expect(rendered.contains("[REDACTED]"), "\(format) is missing the redaction marker")
        }
    }

    @Test("redaction does not mutate the original document")
    func redactionDoesNotMutateModel() throws {
        let needle = "3f2a9c1e-77b4-4c2e-9d1a-0b6e5f4a3c21"
        let document = documentWithIdentifier()
        let exporter = DocumentExporter()
        _ = try exporter.render(document, as: .markdown, options: ExportOptions(redactedIdentifiers: [needle]))

        guard case .title(let text) = document.blocks[0] else {
            Issue.record("expected a title block")
            return
        }
        #expect(text.contains(needle))
    }

    @Test("suggested file name: sanitised stem, extension per format")
    func suggestedFileNameSanitizesStem() {
        let exporter = DocumentExporter()
        // Parentheses aren't in the allowed [A-Za-z0-9 ._-] set, so they're dropped.
        #expect(
            exporter.suggestedFileName(originalName: "Report (final).pdf", format: .markdown)
                == "Report final-clean.md"
        )
        #expect(exporter.suggestedFileName(originalName: "notes.pdf", format: .html) == "notes-clean.html")
    }

    @Test("suggested file name strips characters outside [A-Za-z0-9 ._-]")
    func suggestedFileNameStripsDisallowedCharacters() {
        let name = DocumentExporter().suggestedFileName(originalName: "Q3/Report:2026*.pdf", format: .html)
        #expect(name == "Q3Report2026-clean.html")
    }

    @Test("empty or emoji-only stem falls back to 'document'")
    func emptyOrEmojiStemFallsBack() {
        #expect(DocumentExporter().suggestedFileName(originalName: "", format: .plainText) == "document-clean.txt")
        #expect(
            DocumentExporter().suggestedFileName(originalName: "🎉🎊.pdf", format: .plainText) == "document-clean.txt")
    }

    @Test("neutralFileName option always yields document-clean")
    func neutralFileNameOption() {
        let name = DocumentExporter().suggestedFileName(
            originalName: "Confidential Report.pdf",
            format: .markdown,
            options: ExportOptions(neutralFileName: true)
        )
        #expect(name == "document-clean.md")
    }

    @Test("file extension matches the format")
    func fileExtensionPerFormat() {
        #expect(ExportFormat.markdown.fileExtension == "md")
        #expect(ExportFormat.html.fileExtension == "html")
        #expect(ExportFormat.plainText.fileExtension == "txt")
    }
}
