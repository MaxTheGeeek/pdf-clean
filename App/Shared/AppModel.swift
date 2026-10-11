import Foundation
import Observation
import SwiftUI

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
}
