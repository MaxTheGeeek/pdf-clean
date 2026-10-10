import Foundation

/// Renders an `ExtractedDocument` to Markdown (tech spec §6.10). Blocks are separated by
/// exactly one blank line; the result ends with a single trailing newline; no comments,
/// generator names, dates or metadata are ever emitted.
enum MarkdownRenderer {
    static func render(_ document: ExtractedDocument) -> String {
        let hasTitle = document.blocks.contains { if case .title = $0 { return true } else { return false } }

        var pieces: [String] = []
        var listLines: [String] = []
        var listOrdered: Bool?
        func flushList() {
            guard !listLines.isEmpty else { return }
            pieces.append(listLines.joined(separator: "\n"))
            listLines = []
            listOrdered = nil
        }

        for block in document.blocks {
            if case .listItem(let item) = block {
                if let listOrdered, listOrdered != item.ordered {
                    flushList()
                }
                listOrdered = item.ordered
                listLines.append(renderListItem(item))
                continue
            }
            flushList()
            pieces.append(renderBlock(block, hasTitle: hasTitle))
        }
        flushList()

        let body = pieces.joined(separator: "\n\n")
        return body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func renderBlock(_ block: Block, hasTitle: Bool) -> String {
        switch block {
        case .title(let text):
            return "# \(escape(text))"
        case .heading(let level, let text):
            let hashCount = min(hasTitle ? level + 1 : level, 6)
            return String(repeating: "#", count: max(hashCount, 1)) + " " + escape(text)
        case .paragraph(let text):
            return escape(text)
        case .listItem(let item):
            return renderListItem(item)
        case .tableOfContents(let heading, let entries):
            return renderTOC(heading: heading, entries: entries)
        case .preformatted(let text):
            return "```\n\(text)\n```"
        case .pageBreak:
            return "---"
        }
    }

    private static func renderListItem(_ item: ListItem) -> String {
        let indent = String(repeating: "  ", count: item.level)
        let marker = item.ordered ? "\(orderedNumber(from: item.marker)). " : "- "
        return indent + marker + escape(item.text)
    }

    private static func renderTOC(heading: String?, entries: [TOCEntry]) -> String {
        var lines = ["## \(escape(heading ?? "Contents"))"]
        for entry in entries {
            let indent = String(repeating: "  ", count: max(entry.level - 1, 0))
            var line = indent + "- " + escape(entry.title)
            if let page = entry.page {
                line += " (p. \(escape(page)))"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// Extracts the leading number from an original list marker (e.g. "2." or "2)"),
    /// falling back to "1" when the marker doesn't start with digits.
    private static func orderedNumber(from marker: String) -> String {
        let digits = marker.prefix { $0.isNumber }
        return digits.isEmpty ? "1" : String(digits)
    }

    /// `\`, `` ` ``, `*`, `_`, `[`, `]`, `<`, `>`, `|` anywhere in text, and a leading
    /// `#`, `+`, `-`, `=`, `>` or `\d+[.)]` at the start of any line.
    static func escape(_ text: String) -> String {
        let charactersToEscape: Set<Character> = ["\\", "`", "*", "_", "[", "]", "<", ">", "|"]
        var escaped = ""
        for character in text {
            if charactersToEscape.contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return
            escaped
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(escapeLineStart)
            .joined(separator: "\n")
    }

    private static func escapeLineStart(_ line: Substring) -> String {
        guard let first = line.first else { return String(line) }
        if "#+-=>".contains(first) {
            return "\\" + line
        }
        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber {
            index = line.index(after: index)
        }
        if index > line.startIndex, index < line.endIndex, line[index] == "." || line[index] == ")" {
            return "\\" + line
        }
        return String(line)
    }
}
