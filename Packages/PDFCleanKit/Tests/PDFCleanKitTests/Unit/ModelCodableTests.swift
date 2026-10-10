import Foundation
import Testing

@testable import PDFCleanKit

/// Round-trips every public model type from `specs/02-technical-spec.md` §4-5 through
/// `Codable` (T-004).
@Suite("Model Codable round-trip")
struct ModelCodableTests {
    @Test func extractionOptionsRoundTrips() throws {
        var options = ExtractionOptions()
        options.ocrMode = .always
        options.ocrLanguages = ["fr-FR"]
        options.includePageBreaks = true
        try assertRoundTrips(options)
    }

    @Test func extractedDocumentRoundTrips() throws {
        let document = ExtractedDocument(
            blocks: [
                .title("Title"),
                .heading(level: 1, text: "Heading"),
                .paragraph("Paragraph text."),
                .listItem(ListItem(ordered: true, marker: "1.", level: 0, text: "Item")),
                .tableOfContents(
                    heading: "Contents",
                    entries: [TOCEntry(level: 1, title: "Intro", page: "3")]
                ),
                .preformatted("code"),
                .pageBreak(page: 2),
            ],
            report: SanitizationReport(
                removedHiddenWords: 3,
                suspiciousIdentifiers: [IdentifierFinding(text: "uuid-1", kind: .uuid, occurrences: 1)],
                warnings: [.ocrLowConfidence],
                sourceInventory: SourceInventory(metadataKeys: ["Author"], hasXMP: true)
            ),
            pageCount: 2,
            dominantLanguage: "en-US"
        )
        try assertRoundTrips(document)
    }

    @Test func pipelineEventRoundTrips() throws {
        try assertRoundTrips(
            PipelineEvent.progress(
                PipelineProgress(stage: .cleaning, page: 2, pageCount: 5, fractionCompleted: 0.5)
            )
        )
    }

    @Test func pipelineErrorRoundTrips() throws {
        try assertRoundTrips(PipelineError.tooLarge(pages: 3000, bytes: 10))
        try assertRoundTrips(PipelineError.outputVerificationFailed([.metadataValueLeak, .c0Control(scalar: 7)]))
    }

    @Test func exportOptionsRoundTrips() throws {
        try assertRoundTrips(ExportOptions(redactedIdentifiers: ["a", "b"], neutralFileName: true))
    }

    @Test func counterKeyPathLooksUpEveryManifestCounterName() throws {
        let report = SanitizationReport(removedHiddenWords: 7, removedTinyGlyphs: 2)
        let names = [
            "removedHiddenWords", "removedTinyGlyphs", "removedOffPageWords", "removedRotatedRuns",
            "removedOverlappingDuplicates", "removedRepeatedLines", "removedHeaderFooterLines",
            "removedInvisibleCodepoints", "removedPrivateUseCodepoints", "normalizedHomoglyphs",
            "normalizedWhitespace", "normalizedLigatures",
        ]
        for name in names {
            #expect(SanitizationReport.counterKeyPath(named: name) != nil, "missing key path for \(name)")
        }
        #expect(SanitizationReport.counterKeyPath(named: "notACounter") == nil)

        let keyPath = try #require(SanitizationReport.counterKeyPath(named: "removedHiddenWords"))
        #expect(report[keyPath: keyPath] == 7)
    }

    @Test func exportFormatFileExtensions() {
        #expect(ExportFormat.markdown.fileExtension == "md")
        #expect(ExportFormat.html.fileExtension == "html")
        #expect(ExportFormat.plainText.fileExtension == "txt")
    }
}

private func assertRoundTrips<T: Codable & Equatable>(_ value: T) throws {
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(T.self, from: data)
    #expect(decoded == value)
}
