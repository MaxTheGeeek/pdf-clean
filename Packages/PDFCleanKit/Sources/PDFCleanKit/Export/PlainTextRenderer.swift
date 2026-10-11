import Foundation

/// Renders an `ExtractedDocument` to plain text (tech spec §6.10). No escaping; blocks
/// are separated by exactly one blank line; the result ends with a single newline.
enum PlainTextRenderer {
    static func render(_ document: ExtractedDocument) -> String {
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
            pieces.append(renderBlock(block))
        }
        flushList()

        let body = pieces.joined(separator: "\n\n")
        return body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func renderBlock(_ block: Block) -> String {
        switch block {
        case .title(let text):
            return text + "\n" + String(repeating: "=", count: text.count)
        case .heading(let level, let text):
            if level == 1 {
                return text + "\n" + String(repeating: "-", count: text.count)
            }
            return text
        case .paragraph(let text):
            return text
        case .listItem(let item):
            return renderListItem(item)
        case .tableOfContents(let heading, let entries):
            var lines = [heading ?? "Contents"]
            for entry in entries {
                let indent = String(repeating: "  ", count: max(entry.level - 1, 0))
                var line = indent + entry.title
                if let page = entry.page {
                    line += " \(page)"
                }
                lines.append(line)
            }
            return lines.joined(separator: "\n")
        case .preformatted(let text):
            return text
        case .math(let math):
            return math.kind == .display ? "\n\(math.text)\n" : math.text
        case .pageBreak:
            return "* * *"
        }
    }

    private static func renderListItem(_ item: ListItem) -> String {
        let indent = String(repeating: "  ", count: item.level)
        let marker = item.ordered ? "\(orderedNumber(from: item.marker)). " : "• "
        return indent + marker + item.text
    }

    /// Extracts the leading number from an original list marker, falling back to "1".
    private static func orderedNumber(from marker: String) -> String {
        let digits = marker.prefix { $0.isNumber }
        return digits.isEmpty ? "1" : String(digits)
    }
}
