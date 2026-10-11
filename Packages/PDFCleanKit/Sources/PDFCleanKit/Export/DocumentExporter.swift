import Foundation

/// Renders an `ExtractedDocument` to one of the supported export formats and suggests a
/// file name for it (tech spec §4, §6.9 redaction, §6.10, FR-18, FR-21).
public struct DocumentExporter: Sendable {
    /// Creates an exporter.
    public init() {}

    /// Renders `document` as `format`, applying `options.redactedIdentifiers` without
    /// mutating `document` itself, then runs `OutputVerifier` on the result and throws
    /// `PipelineError.outputVerificationFailed` if it finds anything — nothing is
    /// returned in that case (constitution P2).
    ///
    /// `OutputVerifier`'s source-metadata-value check needs the transient values
    /// collected at ingest, which this type never sees (constitution P4); that part of
    /// the gate is exercised by `ExtractionPipeline` (T-035), not here.
    public func render(
        _ document: ExtractedDocument,
        as format: ExportFormat,
        options: ExportOptions = ExportOptions()
    ) throws -> String {
        let redactedDocument = redacted(document, identifiers: options.redactedIdentifiers)
        let rendered: String
        switch format {
        case .markdown:
            rendered = MarkdownRenderer.render(redactedDocument)
        case .html:
            rendered = HTMLRenderer.render(redactedDocument)
        case .plainText:
            rendered = PlainTextRenderer.render(redactedDocument)
        }

        let violations = OutputVerifier.verify(rendered)
        guard violations.isEmpty else {
            throw PipelineError.outputVerificationFailed(violations)
        }
        return rendered
    }

    /// `<original-stem>-clean.<ext>`, stem sanitised to `[A-Za-z0-9 ._-]`; falls back to
    /// "document" when the sanitised stem is empty or `options.neutralFileName` is set.
    public func suggestedFileName(
        originalName: String,
        format: ExportFormat,
        options: ExportOptions = ExportOptions()
    ) -> String {
        let stem = options.neutralFileName ? "document" : sanitizedStem(from: originalName)
        return "\(stem)-clean.\(format.fileExtension)"
    }

    private func sanitizedStem(from originalName: String) -> String {
        let rawStem = (originalName as NSString).deletingPathExtension
        let allowed: Set<Character> = Set(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ._-"
        )
        let filtered = rawStem.filter { allowed.contains($0) }.trimmingCharacters(in: .whitespaces)
        return filtered.isEmpty ? "document" : filtered
    }

    private func redacted(_ document: ExtractedDocument, identifiers: Set<String>) -> ExtractedDocument {
        guard !identifiers.isEmpty else { return document }
        var copy = document
        copy.blocks = document.blocks.map { redactedBlock($0, identifiers: identifiers) }
        return copy
    }

    private func redactedBlock(_ block: Block, identifiers: Set<String>) -> Block {
        switch block {
        case .title(let text):
            return .title(redactedText(text, identifiers: identifiers))
        case .heading(let level, let text):
            return .heading(level: level, text: redactedText(text, identifiers: identifiers))
        case .paragraph(let text):
            return .paragraph(redactedText(text, identifiers: identifiers))
        case .listItem(var item):
            item.text = redactedText(item.text, identifiers: identifiers)
            return .listItem(item)
        case .tableOfContents(let heading, let entries):
            let redactedHeading = heading.map { redactedText($0, identifiers: identifiers) }
            let redactedEntries = entries.map { entry -> TOCEntry in
                var copy = entry
                copy.title = redactedText(entry.title, identifiers: identifiers)
                return copy
            }
            return .tableOfContents(heading: redactedHeading, entries: redactedEntries)
        case .preformatted(let text):
            return .preformatted(redactedText(text, identifiers: identifiers))
        case .math(let math):
            return .math(MathBlock(text: redactedText(math.text, identifiers: identifiers), kind: math.kind))
        case .pageBreak(let page):
            return .pageBreak(page: page)
        }
    }

    private func redactedText(_ text: String, identifiers: Set<String>) -> String {
        var result = text
        for identifier in identifiers {
            result = result.replacingOccurrences(of: identifier, with: "[REDACTED]")
        }
        return result
    }
}
