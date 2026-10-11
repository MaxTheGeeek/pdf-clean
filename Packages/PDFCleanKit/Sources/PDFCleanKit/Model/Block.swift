import Foundation

/// One structural element of the cleaned document, in reading order (FR-06…FR-10).
public enum Block: Sendable, Equatable, Codable {
    case title(String)
    case heading(level: Int, text: String)
    case paragraph(String)
    case listItem(ListItem)
    case tableOfContents(heading: String?, entries: [TOCEntry])
    case preformatted(String)
    case math(MathBlock)
    case pageBreak(page: Int)
}

/// One inline or display-math region preserved as a math-friendly representation.
public struct MathBlock: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Equatable, Codable {
        case inline
        case display
    }

    public var text: String
    public var kind: Kind

    public init(text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }
}

/// One item of a bulleted or numbered list (FR-10).
public struct ListItem: Sendable, Equatable, Codable {
    /// `true` for a numbered list item, `false` for a bulleted one.
    public var ordered: Bool
    /// The marker as it appeared in the source, e.g. "-", "•" or "2.".
    public var marker: String
    /// Nesting depth, 0 for a top-level item.
    public var level: Int
    /// The item's visible text, marker excluded.
    public var text: String

    /// Creates a list item.
    public init(ordered: Bool, marker: String, level: Int, text: String) {
        self.ordered = ordered
        self.marker = marker
        self.level = level
        self.text = text
    }
}

/// One row of a detected table of contents (FR-08).
public struct TOCEntry: Sendable, Equatable, Codable {
    /// Nesting depth, 1 for a top-level entry.
    public var level: Int
    /// The entry's visible title text.
    public var title: String
    /// Page label as printed (may be roman numerals), `nil` if none was found.
    public var page: String?

    /// Creates a table-of-contents entry.
    public init(level: Int, title: String, page: String? = nil) {
        self.level = level
        self.title = title
        self.page = page
    }
}
