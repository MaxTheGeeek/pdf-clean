import CoreGraphics
import Foundation
@preconcurrency import PDFKit

/// Opens, unlocks and validates a PDF (tech spec §6.1). The caller already owns a private
/// temporary copy of the file (app-level `JobWorkspace`, §9.3) — this type only reads it.
enum DocumentOpener {

    /// A successfully opened, unlocked, within-limits document.
    struct OpenedDocument {
        var document: PDFDocument
        var cgDocument: CGPDFDocument
        var inventory: SourceInventory
        /// Transient Info/XMP values for `OutputVerifier`; never stored in the report.
        var metadataValues: [String]
        var warnings: [ReportWarning]
    }

    static func open(fileURL: URL, password: String?) throws -> OpenedDocument {
        try checkHeaderAndSize(at: fileURL)

        guard let document = PDFDocument(url: fileURL) else { throw PipelineError.unreadablePDF }

        if document.isLocked {
            guard let password, document.unlock(withPassword: password) else {
                throw password == nil ? PipelineError.passwordRequired : PipelineError.wrongPassword
            }
        } else if let password {
            // Not locked for viewing, but a password was supplied: try it as the owner
            // password, which can lift copy/print restrictions without being required to read.
            _ = document.unlock(withPassword: password)
        }

        if !document.allowsCopying {
            guard document.permissionsStatus == .owner else { throw PipelineError.copyingNotPermitted }
        }

        let pageCount = document.pageCount
        guard pageCount > 0 else { throw PipelineError.emptyDocument }
        guard pageCount <= Constants.maxPages else {
            throw PipelineError.tooLarge(pages: pageCount, bytes: fileSize(at: fileURL) ?? 0)
        }
        var warnings: [ReportWarning] = []
        if pageCount > Constants.warnPages { warnings.append(.manyPages) }

        guard let cgDocument = document.documentRef else { throw PipelineError.unreadablePDF }

        let (inventory, metadataValues) = SourceInventoryBuilder.build(document: document, cgDocument: cgDocument)
        return OpenedDocument(
            document: document, cgDocument: cgDocument, inventory: inventory, metadataValues: metadataValues,
            warnings: warnings)
    }

    // MARK: - Header and size

    private static func checkHeaderAndSize(at url: URL) throws {
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw PipelineError.unreadablePDF }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: 1024)) ?? Data()
        guard header.range(of: Data("%PDF-".utf8)) != nil else { throw PipelineError.notAPDF }

        if let size = fileSize(at: url), size > Constants.maxBytes {
            throw PipelineError.tooLarge(pages: 0, bytes: size)
        }
    }

    private static func fileSize(at url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
    }
}
