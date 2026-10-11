import Foundation
import Observation
import SwiftUI
import PDFCleanKit

@MainActor
@Observable
final class AppModel {
    enum Screen {
        case importView
        case awaitingPassword
        case processing
        case result
        case failed
    }

    enum ExportFormat: String, CaseIterable {
        case markdown
        case html
        case plainText

        var title: String {
            switch self {
            case .markdown:
                return "Markdown"
            case .html:
                return "HTML"
            case .plainText:
                return "Plain text"
            }
        }
    }

    struct ReportSummary {
        var hiddenWordsRemoved = 7
        var invisibleCharacters = 14
        var repeatedLinesRemoved = 4
        var identifiers = ["3f2a9c1e-77b4-4c2e-9d1a-0b6e5f4a3c21"]
        var sourceInventory = ["metadata (6 keys)", "XMP", "3 annotations", "1 attachment"]
    }

    var screen: Screen = .importView
    var documentName = "report-q3.pdf"
    var progressStage = "Checking visibility"
    var progressPage = 37
    var pageCount = 120
    var progressFraction = 0.31
    var selectedFormat: ExportFormat = .markdown
    var showSource = false
    var alertTitle = "PDFClean"
    var alertMessage = ""
    var reportSummary = ReportSummary()
    var resultTitle = "Quarterly Infrastructure Report"
    var resultPreview = "This report summarises the migration path and the operational risk review."
    var outlineEntries = [
        "Title",
        "1 Introduction",
        "1.1 Scope",
        "1.2 Priorities",
        "2 Results",
        "2.1 Outcomes",
    ]
    var passwordPromptTitle = "Password needed"
    var passwordPromptDetail = "Enter the PDF password to continue."
    var password = ""
    var passwordRequestIsOwner = false

    func startImport() {
        screen = .importView
        password = ""
        alertMessage = ""
    }

    func open(url: URL) async {
        let startedAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if startedAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let preparedURL: URL
        do {
            preparedURL = try copyToTemporaryLocation(from: url)
        } catch {
            alertTitle = "Open PDF"
            alertMessage = "Could not prepare the selected PDF: \(error.localizedDescription)"
            screen = .failed
            return
        }

        do {
            screen = .processing
            documentName = url.lastPathComponent
            progressStage = "Opening document"
            progressPage = 0
            pageCount = 0
            progressFraction = 0
            alertMessage = ""

            let pipeline = ExtractionPipeline()
            let stream = await pipeline.run(fileURL: preparedURL, password: password)
            var extractedDocument: ExtractedDocument?

            for try await event in stream {
                switch event {
                case .progress(let progress):
                    progressStage = stageLabel(for: progress.stage)
                    progressPage = max(0, progress.page)
                    pageCount = max(0, progress.pageCount)
                    progressFraction = progress.fractionCompleted
                case .finished(let document):
                    extractedDocument = document
                }
            }

            guard let extractedDocument else {
                throw PipelineError.emptyDocument
            }

            apply(document: extractedDocument)
        } catch {
            alertTitle = "Processing failed"
            alertMessage = "The PDF could not be processed: \(error.localizedDescription)"
            screen = .failed
        }
    }

    func beginProcessing() {
        screen = .processing
        progressStage = "Checking visibility"
        progressPage = 37
        pageCount = 120
        progressFraction = 0.31
    }

    func completeProcessing() {
        screen = .result
        progressFraction = 1
    }

    func requirePassword(isOwner: Bool = false) {
        passwordRequestIsOwner = isOwner
        passwordPromptTitle = isOwner ? "Owner password needed" : "Password needed"
        passwordPromptDetail =
            isOwner
            ? "The PDF restricts copying. Unlock it to continue."
            : "Enter the PDF password to continue."
        screen = .awaitingPassword
    }

    func unlockPassword() {
        screen = .processing
        progressStage = "Analyzing layout"
        progressPage = 75
        pageCount = 120
        progressFraction = 0.72
        password = ""
    }

    func cancelProcessing() {
        screen = .importView
        progressFraction = 0
        progressPage = 0
    }

    func newDocument() {
        screen = .importView
        showSource = false
        selectedFormat = .markdown
    }

    private func copyToTemporaryLocation(from url: URL) throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PDFClean-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let destinationURL = tempDirectory.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: url, to: destinationURL)
        return destinationURL
    }

    private func stageLabel(for stage: PipelineProgress.Stage) -> String {
        switch stage {
        case .opening:
            return "Opening document"
        case .readingPages:
            return "Reading pages"
        case .checkingVisibility:
            return "Checking visibility"
        case .recognizingText:
            return "Recognizing text"
        case .analyzingLayout:
            return "Analyzing layout"
        case .cleaning:
            return "Cleaning document"
        case .done:
            return "Complete"
        }
    }

    private func apply(document: ExtractedDocument) {
        let title = document.blocks.compactMap { block -> String? in
            if case .title(let text) = block { return text }
            return nil
        }.first ?? "Untitled PDF"

        let preview = document.blocks.compactMap { block -> String? in
            switch block {
            case .paragraph(let text):
                return text
            default:
                return nil
            }
        }.first ?? "Document processed successfully."

        resultTitle = title
        resultPreview = preview
        pageCount = document.pageCount
        progressStage = "Complete"
        progressFraction = 1
        outlineEntries = document.blocks.map { block in
            switch block {
            case .title(let text):
                return text
            case .heading(let level, let text):
                return String(repeating: "  ", count: level - 1) + text
            case .paragraph(let text):
                return text
            case .listItem(let item):
                return "• \(item.text)"
            case .tableOfContents(let heading, _):
                return heading ?? "Table of contents"
            case .preformatted(let text):
                return text
            case .pageBreak(let page):
                return "Page \(page)"
            }
        }
        reportSummary = ReportSummary()
        screen = .result
    }
}
