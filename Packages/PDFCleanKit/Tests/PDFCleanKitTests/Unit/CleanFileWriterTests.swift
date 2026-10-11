import Foundation
import Testing

@testable import PDFCleanKit

#if os(macOS)
    import Darwin
#endif

/// Writer test (T-014): no BOM, LF only, final newline, xattrs removed (macOS).
@Suite("CleanFileWriter")
struct CleanFileWriterTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanFileWriterTests-\(UUID().uuidString).txt")
    }

    @Test("writes UTF-8 with no BOM and the exact bytes given")
    func noBOM() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try CleanFileWriter().write("Hello, world.\n", to: url)
        let data = try Data(contentsOf: url)

        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        #expect(!data.starts(with: bom))
        #expect(data == Data("Hello, world.\n".utf8))
    }

    @Test("preserves LF line endings exactly as given, with a final newline")
    func lfAndFinalNewline() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try CleanFileWriter().write("Line one.\nLine two.\n", to: url)
        let text = try String(contentsOf: url, encoding: .utf8)

        #expect(!text.contains("\r"))
        #expect(text.hasSuffix("\n"))
        #expect(text == "Line one.\nLine two.\n")
    }

    #if os(macOS)
        @Test("strips extended attributes on macOS")
        func stripsExtendedAttributes() throws {
            let url = temporaryURL()
            defer { try? FileManager.default.removeItem(at: url) }

            try CleanFileWriter().write("content\n", to: url)
            Data("quarantine-test".utf8).withUnsafeBytes { bytes in
                _ = setxattr(url.path, "com.apple.test.attribute", bytes.baseAddress, bytes.count, 0, 0)
            }
            #expect(listxattr(url.path, nil, 0, 0) > 0)

            try CleanFileWriter().write("content\n", to: url)
            #expect(listxattr(url.path, nil, 0, 0) == 0)
        }
    #endif
}
