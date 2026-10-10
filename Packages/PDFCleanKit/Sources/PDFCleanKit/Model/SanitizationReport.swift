import Foundation

/// What was removed or changed while cleaning the document (FR-18, FR-19) — counts and
/// findings only; never the removed text itself (constitution P4).
public struct SanitizationReport: Sendable, Equatable, Codable {
    /// Words removed because they were invisible (sanitisation spec §3).
    public var removedHiddenWords: Int
    /// Glyphs removed for being smaller than `Constants.minFontSize`.
    public var removedTinyGlyphs: Int
    /// Words removed for being mostly outside the page.
    public var removedOffPageWords: Int
    /// Rotated watermark glyph runs removed.
    public var removedRotatedRuns: Int
    /// Duplicate words removed by overlap dedupe (sanitisation spec §4).
    public var removedOverlappingDuplicates: Int
    /// Lines removed by the repeated-content filter, Rule B/C (sanitisation spec §5).
    public var removedRepeatedLines: Int
    /// Lines removed as repeated headers/footers, Rule A (sanitisation spec §5).
    public var removedHeaderFooterLines: Int
    /// Invisible/format Unicode code points removed from word text (sanitisation spec §6).
    public var removedInvisibleCodepoints: Int
    /// Private-use-area code points removed from word text.
    public var removedPrivateUseCodepoints: Int
    /// Homoglyph/lookalike characters normalised to their plain-script form.
    public var normalizedHomoglyphs: Int
    /// Whitespace runs normalised (Zs collapsed to a single space, outside preformatted).
    public var normalizedWhitespace: Int
    /// Ligatures decomposed to their constituent letters.
    public var normalizedLigatures: Int
    /// 1-based page numbers where OCR ran.
    public var ocrPages: [Int]
    /// Redactable strings found in the visible text (FR-18).
    public var suspiciousIdentifiers: [IdentifierFinding]
    /// Non-fatal conditions to surface to the user.
    public var warnings: [ReportWarning]
    /// Non-identifying facts about the source PDF (FR-17, FR-19).
    public var sourceInventory: SourceInventory

    /// Creates a report, defaulting to all-zero counters and an empty inventory.
    public init(
        removedHiddenWords: Int = 0,
        removedTinyGlyphs: Int = 0,
        removedOffPageWords: Int = 0,
        removedRotatedRuns: Int = 0,
        removedOverlappingDuplicates: Int = 0,
        removedRepeatedLines: Int = 0,
        removedHeaderFooterLines: Int = 0,
        removedInvisibleCodepoints: Int = 0,
        removedPrivateUseCodepoints: Int = 0,
        normalizedHomoglyphs: Int = 0,
        normalizedWhitespace: Int = 0,
        normalizedLigatures: Int = 0,
        ocrPages: [Int] = [],
        suspiciousIdentifiers: [IdentifierFinding] = [],
        warnings: [ReportWarning] = [],
        sourceInventory: SourceInventory = SourceInventory()
    ) {
        self.removedHiddenWords = removedHiddenWords
        self.removedTinyGlyphs = removedTinyGlyphs
        self.removedOffPageWords = removedOffPageWords
        self.removedRotatedRuns = removedRotatedRuns
        self.removedOverlappingDuplicates = removedOverlappingDuplicates
        self.removedRepeatedLines = removedRepeatedLines
        self.removedHeaderFooterLines = removedHeaderFooterLines
        self.removedInvisibleCodepoints = removedInvisibleCodepoints
        self.removedPrivateUseCodepoints = removedPrivateUseCodepoints
        self.normalizedHomoglyphs = normalizedHomoglyphs
        self.normalizedWhitespace = normalizedWhitespace
        self.normalizedLigatures = normalizedLigatures
        self.ocrPages = ocrPages
        self.suspiciousIdentifiers = suspiciousIdentifiers
        self.warnings = warnings
        self.sourceInventory = sourceInventory
    }

    /// Maps a manifest counter name (`specs/05-test-plan.md` §2, `reportAtLeast` /
    /// `reportExactly`) to the `SanitizationReport` property it checks. Used by the
    /// fixture harness (T-035) to look counters up generically by name.
    ///
    /// A function rather than a stored dictionary: `KeyPath` is not `Sendable`, so a
    /// static dictionary literal of key paths fails Swift 6's strict-concurrency check
    /// on shared global state.
    public static func counterKeyPath(named name: String) -> KeyPath<SanitizationReport, Int>? {
        switch name {
        case "removedHiddenWords": return \.removedHiddenWords
        case "removedTinyGlyphs": return \.removedTinyGlyphs
        case "removedOffPageWords": return \.removedOffPageWords
        case "removedRotatedRuns": return \.removedRotatedRuns
        case "removedOverlappingDuplicates": return \.removedOverlappingDuplicates
        case "removedRepeatedLines": return \.removedRepeatedLines
        case "removedHeaderFooterLines": return \.removedHeaderFooterLines
        case "removedInvisibleCodepoints": return \.removedInvisibleCodepoints
        case "removedPrivateUseCodepoints": return \.removedPrivateUseCodepoints
        case "normalizedHomoglyphs": return \.normalizedHomoglyphs
        case "normalizedWhitespace": return \.normalizedWhitespace
        case "normalizedLigatures": return \.normalizedLigatures
        default: return nil
        }
    }
}

/// Non-identifying facts about the source PDF (FR-17, FR-19) — keys and counts only;
/// metadata values are never stored (constitution P4).
public struct SourceInventory: Sendable, Equatable, Codable {
    /// The PDF's declared version string, e.g. "1.7".
    public var pdfVersion: String
    /// Whether the source file was encrypted.
    public var isEncrypted: Bool
    /// Info dictionary and XMP key names present in the source — never their values.
    public var metadataKeys: [String]
    /// Whether the source has an XMP metadata stream.
    public var hasXMP: Bool
    /// Whether the source has a PDF outline (bookmarks).
    public var hasOutline: Bool
    /// Whether the source has AcroForm fields.
    public var hasFormFields: Bool
    /// Whether the source has embedded JavaScript.
    public var hasJavaScript: Bool
    /// Number of annotations found.
    public var annotationCount: Int
    /// Number of embedded files/attachments found.
    public var embeddedFileCount: Int

    /// Creates an inventory, defaulting to an unencrypted document with nothing found.
    public init(
        pdfVersion: String = "",
        isEncrypted: Bool = false,
        metadataKeys: [String] = [],
        hasXMP: Bool = false,
        hasOutline: Bool = false,
        hasFormFields: Bool = false,
        hasJavaScript: Bool = false,
        annotationCount: Int = 0,
        embeddedFileCount: Int = 0
    ) {
        self.pdfVersion = pdfVersion
        self.isEncrypted = isEncrypted
        self.metadataKeys = metadataKeys
        self.hasXMP = hasXMP
        self.hasOutline = hasOutline
        self.hasFormFields = hasFormFields
        self.hasJavaScript = hasJavaScript
        self.annotationCount = annotationCount
        self.embeddedFileCount = embeddedFileCount
    }
}

/// A redactable string that matched a known identifier pattern (FR-18).
public struct IdentifierFinding: Sendable, Equatable, Codable {
    /// The kind of pattern matched.
    public enum Kind: String, Sendable, Equatable, Codable {
        case uuid, hex, base64Token, jwt, email, keyPattern
    }

    /// The exact matched text, as it appears in the visible document.
    public var text: String
    /// The kind of pattern matched.
    public var kind: Kind
    /// Number of times this exact text occurs in the document.
    public var occurrences: Int

    /// Creates an identifier finding.
    public init(text: String, kind: Kind, occurrences: Int) {
        self.text = text
        self.kind = kind
        self.occurrences = occurrences
    }
}

/// A non-fatal condition surfaced to the user, e.g. in the result screen's report panel.
public enum ReportWarning: String, Sendable, Equatable, Codable {
    case manyPages, ocrLowConfidence, unreadableCharacters, rtlBasicSupport
}
