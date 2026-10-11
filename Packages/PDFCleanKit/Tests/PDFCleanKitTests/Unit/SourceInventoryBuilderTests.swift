import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U29 (T-030): `SourceInventoryBuilder` on real fixtures — only metadata *keys* (never
/// values) are collected, and the inventory matches the manifest's expectations.
@Suite("SourceInventoryBuilder")
struct SourceInventoryBuilderTests {

    @Test("hidden-content: metadata keys, XMP, form fields, annotations and an attachment")
    func hiddenContentInventory() throws {
        let opened = try DocumentOpener.open(fileURL: fixtureURL("hidden-content"), password: nil)
        let inventory = opened.inventory

        #expect(inventory.hasXMP)
        #expect(inventory.hasFormFields)
        #expect(inventory.embeddedFileCount == 1)
        #expect(inventory.annotationCount >= 3)
        #expect(
            Set(["Author", "Creator", "Keywords", "Producer", "Title", "TrackingID"]).isSubset(
                of: inventory.metadataKeys))

        // Values are never collected into the inventory — only key names.
        for key in inventory.metadataKeys {
            #expect(!key.contains("CANARY"))
        }
    }

    @Test("toc: has a PDF outline, no XMP, no attachments")
    func tocInventory() throws {
        let opened = try DocumentOpener.open(fileURL: fixtureURL("toc"), password: nil)
        #expect(opened.inventory.hasOutline)
        #expect(!opened.inventory.hasXMP)
        #expect(opened.inventory.embeddedFileCount == 0)
    }

    @Test("encoding the inventory to JSON never contains a metadata value")
    func encodedInventoryContainsNoValues() throws {
        let opened = try DocumentOpener.open(fileURL: fixtureURL("hidden-content"), password: nil)
        let json = try JSONEncoder().encode(opened.inventory)
        let text = String(decoding: json, as: UTF8.self)

        // The report only ever stores keys; none of the collected transient metadata values
        // (held separately for OutputVerifier) should appear in the encoded inventory.
        for value in opened.metadataValues {
            #expect(!text.contains(value))
        }
    }

    @Test("metadata values are collected transiently, at least 6 characters each")
    func metadataValuesCollected() throws {
        let opened = try DocumentOpener.open(fileURL: fixtureURL("hidden-content"), password: nil)
        #expect(!opened.metadataValues.isEmpty)
        for value in opened.metadataValues {
            #expect(value.count >= 6)
        }
    }

    // MARK: - Fixtures

    func fixtureURL(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: "pdf", subdirectory: "Fixtures"))
    }
}
