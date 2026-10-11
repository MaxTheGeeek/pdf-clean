import Foundation

/// Final safety gate before writing an export (sanitisation spec §9, constitution P2): a
/// defense-in-depth re-scan of the fully rendered text for anything `UnicodeSanitizer`
/// should already have removed, plus a check that no raw source metadata value leaked
/// through. A non-empty result is a bug and blocks the export.
enum OutputVerifier {
    /// `inventoryValues` are the transient source metadata values (Info/XMP text, length
    /// ≥ 6) collected at ingest and held only in memory — never stored in the report.
    /// The caller is expected to have already excluded values that legitimately appear
    /// among the document's own visible words.
    static func verify(_ text: String, inventoryValues: [String] = []) -> [OutputViolation] {
        var violations: [OutputViolation] = []
        let scalars = Array(text.unicodeScalars)
        for index in scalars.indices {
            let previous: Unicode.Scalar? = index > 0 ? scalars[index - 1] : nil
            let next: Unicode.Scalar? = index + 1 < scalars.count ? scalars[index + 1] : nil
            if let violation = violation(for: scalars[index], previous: previous, next: next) {
                violations.append(violation)
            }
        }
        for value in inventoryValues where value.count >= 6 && text.contains(value) {
            violations.append(.metadataValueLeak)
        }
        return violations
    }

    private static func violation(
        for scalar: Unicode.Scalar,
        previous: Unicode.Scalar?,
        next: Unicode.Scalar?
    ) -> OutputViolation? {
        // Always allowed: LF, TAB (preformatted text relies on it surviving), plain space.
        if scalar.value == 0x0A || scalar.value == 0x09 || scalar.value == 0x20 {
            return nil
        }
        if isC0OrC1Control(scalar) {
            return .c0Control(scalar: scalar.value)
        }
        if scalar.properties.generalCategory == .spaceSeparator {
            return .nonASCIISpace(scalar: scalar.value)
        }
        if scalar.value == 0x200C || scalar.value == 0x200D {
            return UnicodeTables.shouldKeepJoiner(scalar, previous: previous, next: next)
                ? nil : .forbiddenCodepoint(scalar: scalar.value)
        }
        if scalar.value == 0xFE0E || scalar.value == 0xFE0F {
            return (previous?.properties.isEmoji ?? false) ? nil : .forbiddenCodepoint(scalar: scalar.value)
        }
        // Soft hyphen never legitimately survives sanitising: it is always either
        // removed or turned into a plain hyphen.
        if scalar.value == 0x00AD {
            return .forbiddenCodepoint(scalar: scalar.value)
        }
        if scalar.value == 0xFFFD
            || UnicodeTables.isPrivateUse(scalar)
            || UnicodeTables.isUnconditionallyRemoved(scalar)
            || UnicodeTables.isUnassignedOrLeftoverFormat(scalar)
        {
            return .forbiddenCodepoint(scalar: scalar.value)
        }
        return nil
    }

    private static func isC0OrC1Control(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x08, 0x0B...0x1F, 0x7F, 0x80...0x9F:
            return true
        default:
            return false
        }
    }
}
