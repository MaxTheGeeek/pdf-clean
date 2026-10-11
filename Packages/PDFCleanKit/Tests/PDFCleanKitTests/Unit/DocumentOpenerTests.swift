import Foundation
import Testing

@testable import PDFCleanKit

/// T-030: `DocumentOpener` against the real fixture PDFs — the header/validity, password and
/// copy-permission paths of tech spec §6.1 (FR-02, FR-03).
@Suite("DocumentOpener")
struct DocumentOpenerTests {

    @Test("a file without a %PDF- header is rejected as not a PDF")
    func notAPDF() throws {
        let url = try fixtureURL("not-a-pdf")
        #expect(throws: PipelineError.notAPDF) {
            _ = try DocumentOpener.open(fileURL: url, password: nil)
        }
    }

    @Test("a truncated file never crashes — it opens or throws a PipelineError")
    func truncatedDoesNotCrash() throws {
        let url = try fixtureURL("truncated")
        do {
            _ = try DocumentOpener.open(fileURL: url, password: nil)
        } catch is PipelineError {
            // Also acceptable: a PipelineError, not a crash.
        }
    }

    @Test("an encrypted PDF with no password requires one")
    func encryptedMissingPassword() throws {
        let url = try fixtureURL("encrypted-user-password")
        #expect(throws: PipelineError.passwordRequired) {
            _ = try DocumentOpener.open(fileURL: url, password: nil)
        }
    }

    @Test("an encrypted PDF with the wrong password is rejected")
    func encryptedWrongPassword() throws {
        let url = try fixtureURL("encrypted-user-password")
        #expect(throws: PipelineError.wrongPassword) {
            _ = try DocumentOpener.open(fileURL: url, password: "wrong")
        }
    }

    @Test("an encrypted PDF with the correct password opens")
    func encryptedCorrectPassword() throws {
        let url = try fixtureURL("encrypted-user-password")
        let opened = try DocumentOpener.open(fileURL: url, password: "open-sesame")
        #expect(opened.document.pageCount > 0)
        #expect(opened.inventory.isEncrypted)
    }

    @Test("a copy-restricted PDF with no password is refused")
    func copyRestrictedNoPassword() throws {
        let url = try fixtureURL("copy-restricted")
        #expect(throws: PipelineError.copyingNotPermitted) {
            _ = try DocumentOpener.open(fileURL: url, password: nil)
        }
    }

    @Test("a copy-restricted PDF with the owner password opens")
    func copyRestrictedOwnerPassword() throws {
        let url = try fixtureURL("copy-restricted")
        let opened = try DocumentOpener.open(fileURL: url, password: "owner-only")
        #expect(opened.document.pageCount > 0)
    }

    @Test("a plain, unencrypted PDF opens with no password")
    func plainDocumentOpens() throws {
        let url = try fixtureURL("simple-structured")
        let opened = try DocumentOpener.open(fileURL: url, password: nil)
        #expect(opened.document.pageCount > 0)
        #expect(!opened.inventory.isEncrypted)
    }

    // MARK: - Fixtures

    func fixtureURL(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: "pdf", subdirectory: "Fixtures"))
    }
}
