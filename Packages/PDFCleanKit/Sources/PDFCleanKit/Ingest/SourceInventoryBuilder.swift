import CoreGraphics
@preconcurrency import PDFKit

/// Builds the non-identifying `SourceInventory` (FR-17, FR-19) from a document's catalog and
/// Info dictionary — key *names* and presence/counts only, never values (constitution P4).
enum SourceInventoryBuilder {

    /// `metadataValues` (transient, Info string values + XMP text snippets) is returned
    /// separately for `OutputVerifier`; it must never be stored in the report.
    static func build(
        document: PDFDocument, cgDocument: CGPDFDocument
    ) -> (
        inventory: SourceInventory, metadataValues: [String]
    ) {
        let catalog = cgDocument.catalog
        let info = cgDocument.info

        var inventory = SourceInventory()
        inventory.pdfVersion = "\(document.majorVersion).\(document.minorVersion)"
        inventory.isEncrypted = document.isEncrypted
        inventory.metadataKeys = infoKeys(of: info).sorted()
        inventory.hasXMP = catalog.flatMap { dictionaryContainsStream($0, "Metadata") } ?? false
        inventory.hasOutline = (document.outlineRoot?.numberOfChildren ?? 0) > 0
        inventory.hasFormFields = catalog.flatMap { dictionaryContainsDictionary($0, "AcroForm") } ?? false
        inventory.hasJavaScript = catalog.map(hasJavaScript) ?? false
        inventory.annotationCount = (0..<document.pageCount).reduce(0) { total, i in
            total + (document.page(at: i)?.annotations.count ?? 0)
        }
        inventory.embeddedFileCount = catalog.map(embeddedFileCount) ?? 0

        let metadataValues = MetadataValues.collect(info: info, catalog: catalog)
        return (inventory, metadataValues)
    }

    // MARK: - Info keys

    private static func infoKeys(of info: CGPDFDictionaryRef?) -> [String] {
        guard let info else { return [] }
        var keys: [String] = []
        CGPDFDictionaryApplyBlock(
            info,
            { key, _, context in
                guard let context else { return true }
                let keys = context.assumingMemoryBound(to: [String].self)
                keys.pointee.append(String(cString: key))
                return true
            },
            withUnsafeMutablePointer(to: &keys) { UnsafeMutableRawPointer($0) }
        )
        return keys
    }

    // MARK: - Catalog presence checks

    private static func dictionaryContainsStream(_ dict: CGPDFDictionaryRef, _ key: String) -> Bool {
        var stream: CGPDFStreamRef?
        return CGPDFDictionaryGetStream(dict, key, &stream)
    }

    private static func dictionaryContainsDictionary(_ dict: CGPDFDictionaryRef, _ key: String) -> Bool {
        var child: CGPDFDictionaryRef?
        return CGPDFDictionaryGetDictionary(dict, key, &child)
    }

    private static func hasJavaScript(in catalog: CGPDFDictionaryRef) -> Bool {
        if let names = namesDictionary(of: catalog, named: "JavaScript"), countNameTreeLeaves(names) > 0 {
            return true
        }
        var openAction: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(catalog, "OpenAction", &openAction), let openAction {
            var actionType: UnsafePointer<Int8>?
            if CGPDFDictionaryGetName(openAction, "S", &actionType), let actionType,
                String(cString: actionType) == "JavaScript"
            {
                return true
            }
        }
        return false
    }

    private static func embeddedFileCount(in catalog: CGPDFDictionaryRef) -> Int {
        guard let embeddedFiles = namesDictionary(of: catalog, named: "EmbeddedFiles") else { return 0 }
        return countNameTreeLeaves(embeddedFiles)
    }

    /// The sub-dictionary `catalog.Names.<named>` (a PDF name tree root), if present.
    private static func namesDictionary(of catalog: CGPDFDictionaryRef, named name: String) -> CGPDFDictionaryRef? {
        var names: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "Names", &names), let names else { return nil }
        var target: CGPDFDictionaryRef?
        _ = CGPDFDictionaryGetDictionary(names, name, &target)
        return target
    }

    /// Leaf count of a PDF name tree node: either a flat `Names` array (one leaf per
    /// name/value pair) or `Kids` sub-nodes to recurse into.
    private static func countNameTreeLeaves(_ node: CGPDFDictionaryRef) -> Int {
        var names: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(node, "Names", &names), let names {
            return CGPDFArrayGetCount(names) / 2
        }
        var kids: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(node, "Kids", &kids), let kids {
            var total = 0
            for i in 0..<CGPDFArrayGetCount(kids) {
                var kid: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(kids, i, &kid), let kid {
                    total += countNameTreeLeaves(kid)
                }
            }
            return total
        }
        return 0
    }
}
