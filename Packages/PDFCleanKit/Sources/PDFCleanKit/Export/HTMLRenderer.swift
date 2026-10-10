import Foundation

/// Renders an `ExtractedDocument` to a self-contained HTML document (tech spec §6.10):
/// the exact skeleton the spec gives, no scripts, no external resources, no meta tags
/// beyond charset/viewport.
enum HTMLRenderer {
    static func render(_ document: ExtractedDocument) -> String {
        let title = document.blocks.compactMap { block -> String? in
            if case .title(let text) = block { return text }
            return nil
        }.first
        let lang = document.dominantLanguage ?? "und"

        var html = "<!doctype html>"
        html += "<html lang=\"\(escape(lang))\">"
        html += "<head>"
        html += "<meta charset=\"utf-8\">"
        html += "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
        html += "<title>\(escape(title ?? "Document"))</title>"
        html += "<style>\(PrintCSS.css)</style>"
        html += "</head>"
        html += "<body><main>"
        html += renderBlocks(document.blocks)
        html += "</main></body></html>"
        return html + "\n"
    }

    /// Opens/closes nested `<ul>`/`<ol>` as consecutive `listItem` blocks change level or
    /// ordered-ness; every open level always has exactly one unclosed `<li>` pending,
    /// closed either by the next sibling at that level or when the list ends. Each run
    /// of consecutive list items becomes a single entry in `pieces` (no blank lines
    /// inside one list's markup — those only separate top-level blocks).
    private static func renderBlocks(_ blocks: [Block]) -> String {
        var pieces: [String] = []
        var listBuffer = ""
        var stack: [Bool] = []

        func closeLists(to depth: Int) {
            while stack.count > depth {
                listBuffer += "</li>"
                listBuffer += stack.removeLast() ? "</ol>" : "</ul>"
            }
        }

        func flushList() {
            closeLists(to: 0)
            if !listBuffer.isEmpty {
                pieces.append(listBuffer)
                listBuffer = ""
            }
        }

        for block in blocks {
            guard case .listItem(let item) = block else {
                flushList()
                pieces.append(renderBlock(block))
                continue
            }

            if stack.count > item.level + 1 {
                closeLists(to: item.level + 1)
            }
            if stack.count == item.level + 1, stack[item.level] != item.ordered {
                closeLists(to: item.level)
            }
            if stack.count <= item.level {
                while stack.count < item.level {
                    listBuffer += item.ordered ? "<ol>" : "<ul>"
                    stack.append(item.ordered)
                }
                listBuffer += item.ordered ? "<ol>" : "<ul>"
                stack.append(item.ordered)
            } else {
                listBuffer += "</li>"
            }
            listBuffer += "<li>\(escape(item.text))"
        }
        flushList()
        return pieces.joined(separator: "\n\n")
    }

    private static func renderBlock(_ block: Block) -> String {
        switch block {
        case .title(let text):
            return "<h1>\(escape(text))</h1>"
        case .heading(let level, let text):
            return "<h\(level + 1)>\(escape(text))</h\(level + 1)>"
        case .paragraph(let text):
            return "<p>\(escape(text))</p>"
        case .listItem(let item):
            // Reached only if encountered outside renderBlocks' list-stack handling;
            // kept for exhaustiveness.
            return "<li>\(escape(item.text))</li>"
        case .tableOfContents(let heading, let entries):
            return renderTOC(heading: heading, entries: entries)
        case .preformatted(let text):
            return "<pre>\(escape(text))</pre>"
        case .pageBreak:
            return "<hr>"
        }
    }

    private static func renderTOC(heading: String?, entries: [TOCEntry]) -> String {
        var html = "<nav><h2>\(escape(heading ?? "Contents"))</h2>"
        var levelStack: [Int] = []
        for entry in entries {
            while let top = levelStack.last, top > entry.level {
                html += "</li></ol>"
                levelStack.removeLast()
            }
            if levelStack.last == entry.level {
                html += "</li>"
            } else {
                html += "<ol>"
                levelStack.append(entry.level)
            }
            html += "<li>\(escape(entry.title))"
            if let page = entry.page {
                html += " (p. \(escape(page)))"
            }
        }
        html += String(repeating: "</li></ol>", count: levelStack.count)
        html += "</nav>"
        return html
    }

    /// Escapes `& < > " '` for safe inclusion in HTML text and attributes.
    static func escape(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&#39;"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}
