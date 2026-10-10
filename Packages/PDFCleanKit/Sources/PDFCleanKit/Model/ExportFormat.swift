import Foundation

/// Output file format (FR-21).
public enum ExportFormat: String, CaseIterable, Sendable, Equatable, Codable {
    case markdown, html, plainText

    /// File extension without the leading dot.
    public var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .html: return "html"
        case .plainText: return "txt"
        }
    }
}

/// Export-time options independent of extraction (FR-21, FR-18).
public struct ExportOptions: Sendable, Equatable, Codable {
    /// Exact identifier strings (from `SanitizationReport.suspiciousIdentifiers`) to
    /// replace with a placeholder at render time.
    public var redactedIdentifiers: Set<String>
    /// Use a neutral suggested file name instead of one derived from the document title.
    public var neutralFileName: Bool

    /// Creates export options, defaulting to no redactions and a title-derived file name.
    public init(redactedIdentifiers: Set<String> = [], neutralFileName: Bool = false) {
        self.redactedIdentifiers = redactedIdentifiers
        self.neutralFileName = neutralFileName
    }
}
