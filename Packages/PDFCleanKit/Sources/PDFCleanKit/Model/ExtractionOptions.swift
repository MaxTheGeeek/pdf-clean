import Foundation

/// User-configurable options for the extraction pipeline (FR-05, FR-12, FR-13, FR-15, FR-16).
public struct ExtractionOptions: Sendable, Equatable, Codable {
    /// When OCR runs: automatically on pages that need it, never, or always.
    public enum OCRMode: String, Sendable, Equatable, Codable {
        case auto, off, always
    }

    /// OCR trigger mode (FR-05).
    public var ocrMode: OCRMode
    /// Vision recognition languages, in priority order.
    public var ocrLanguages: [String]
    /// Remove repeated header/footer lines in the page margins (FR-12).
    public var removeHeadersFooters: Bool
    /// Remove lines that repeat across most pages outside the margin bands (FR-16).
    public var removeRepeatedLines: Bool
    /// Remove rotated watermark text runs (FR-13).
    public var removeRotatedText: Bool
    /// Normalise homoglyphs and lookalike characters to their plain-script form (FR-15).
    public var normalizeLookalikes: Bool
    /// Include page numbers when rendering a detected table of contents (FR-08).
    public var includeTOCPageNumbers: Bool
    /// Render a thematic break between pages.
    public var includePageBreaks: Bool

    /// Creates options, defaulting to the recommended settings for most documents.
    public init(
        ocrMode: OCRMode = .auto,
        ocrLanguages: [String] = ["en-US", "de-DE"],
        removeHeadersFooters: Bool = true,
        removeRepeatedLines: Bool = true,
        removeRotatedText: Bool = true,
        normalizeLookalikes: Bool = true,
        includeTOCPageNumbers: Bool = true,
        includePageBreaks: Bool = false
    ) {
        self.ocrMode = ocrMode
        self.ocrLanguages = ocrLanguages
        self.removeHeadersFooters = removeHeadersFooters
        self.removeRepeatedLines = removeRepeatedLines
        self.removeRotatedText = removeRotatedText
        self.normalizeLookalikes = normalizeLookalikes
        self.includeTOCPageNumbers = includeTOCPageNumbers
        self.includePageBreaks = includePageBreaks
    }
}
