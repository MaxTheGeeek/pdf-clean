import Foundation

/// The fully extracted, sanitised, structured document — the pipeline's final output.
public struct ExtractedDocument: Sendable, Equatable, Codable {
    /// The document's content, in reading order.
    public var blocks: [Block]
    /// What was removed or changed while cleaning the document.
    public var report: SanitizationReport
    /// Number of pages in the source PDF.
    public var pageCount: Int
    /// BCP-47 language tag detected by `NLLanguageRecognizer`, if any.
    public var dominantLanguage: String?

    /// Creates an extracted document.
    public init(
        blocks: [Block],
        report: SanitizationReport,
        pageCount: Int,
        dominantLanguage: String? = nil
    ) {
        self.blocks = blocks
        self.report = report
        self.pageCount = pageCount
        self.dominantLanguage = dominantLanguage
    }
}
