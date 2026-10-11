import CoreGraphics
import Foundation

/// Collects source-metadata *values* transiently, for `OutputVerifier` to check that none of
/// them leaked into the exported text (sanitisation spec §9). Never stored in
/// `SanitizationReport` or logged (constitution P4) — the caller must discard this array once
/// verification is done.
enum MetadataValues {

    /// Info dictionary string values and XMP text snippets, each at least 6 characters
    /// (sanitisation spec §9).
    static func collect(info: CGPDFDictionaryRef?, catalog: CGPDFDictionaryRef?) -> [String] {
        var values: [String] = []
        if let info {
            values += infoStringValues(of: info)
        }
        if let catalog, let xmp = xmpStream(of: catalog) {
            values += xmpTextSnippets(of: xmp)
        }
        return values.filter { $0.count >= 6 }
    }

    // MARK: - Info dictionary values

    private static func infoStringValues(of info: CGPDFDictionaryRef) -> [String] {
        var values: [String] = []
        CGPDFDictionaryApplyBlock(
            info,
            { _, object, context in
                guard let context else { return true }
                var stringRef: CGPDFStringRef?
                if CGPDFObjectGetValue(object, .string, &stringRef), let stringRef,
                    let text = CGPDFStringCopyTextString(stringRef) as String?
                {
                    let values = context.assumingMemoryBound(to: [String].self)
                    values.pointee.append(text)
                }
                return true
            },
            withUnsafeMutablePointer(to: &values) { UnsafeMutableRawPointer($0) }
        )
        return values
    }

    // MARK: - XMP text

    private static func xmpStream(of catalog: CGPDFDictionaryRef) -> CGPDFStreamRef? {
        var stream: CGPDFStreamRef?
        _ = CGPDFDictionaryGetStream(catalog, "Metadata", &stream)
        return stream
    }

    /// Text found between XML tags in the raw XMP packet, each run at least 6 characters.
    /// Avoids a full XML/RDF parser (no third-party dependencies, constitution P1) while still
    /// catching the human-readable metadata values XMP actually carries (title, description,
    /// creator, etc.).
    private static func xmpTextSnippets(of stream: CGPDFStreamRef) -> [String] {
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format) as Data? else { return [] }
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        return xml.matches(of: #/>([^<>]{6,}?)</#).map { String($0.1).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
