import Foundation

/// Static lookup tables for `UnicodeSanitizer` (sanitisation spec §6). Kept separate from
/// the algorithm so the data — easy to audit against the spec's code point lists — isn't
/// buried in control flow.
enum UnicodeTables {
    /// Symbol-font private-use bullets that map to a plain bullet (sanitisation spec §6 step 1).
    static let puaBullets: [Unicode.Scalar: Unicode.Scalar] = [
        "\u{F0B7}": "\u{2022}",
        "\u{F0A7}": "\u{2022}",
        "\u{F076}": "\u{2022}",
        "\u{F0D8}": "\u{2022}",
        "\u{F0FC}": "\u{2022}",
        "\u{F06E}": "\u{2022}",
    ]

    /// Ligature code points that decompose to their constituent letters (sanitisation spec §6 step 2).
    static let ligatures: [Unicode.Scalar: String] = [
        "\u{FB00}": "ff",
        "\u{FB01}": "fi",
        "\u{FB02}": "fl",
        "\u{FB03}": "ffi",
        "\u{FB04}": "ffl",
        "\u{FB05}": "st",
        "\u{FB06}": "st",
    ]

    /// `true` for every code point in the §6 step 3 removal list, **except** the ones that
    /// need neighbour context (soft hyphen, ZWNJ/ZWJ, FE0E/FE0F, replacement character) and
    /// private-use code points, which the caller handles separately.
    static func isUnconditionallyRemoved(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        // C0 controls except LF (0x0A) and TAB (0x09, handled by whitespace normalisation).
        case 0x00...0x08, 0x0B...0x1F:
            return true
        // DEL, C1 controls.
        case 0x7F, 0x80...0x9F:
            return true
        // CGJ, ALM.
        case 0x034F, 0x061C:
            return true
        // Hangul fillers.
        case 0x115F, 0x1160, 0x3164, 0xFFA0:
            return true
        // Khmer inherent vowels (invisible).
        case 0x17B4, 0x17B5:
            return true
        // Mongolian variation selectors / vowel separator.
        case 0x180B...0x180F:
            return true
        // ZWSP.
        case 0x200B:
            return true
        // LRM, RLM.
        case 0x200E, 0x200F:
            return true
        // Explicit directional embeddings/overrides.
        case 0x202A...0x202E:
            return true
        // Directional isolates.
        case 0x2066...0x2069:
            return true
        // Word joiner, invisible math operators.
        case 0x2060...0x2064:
            return true
        // Deprecated format characters.
        case 0x206A...0x206F:
            return true
        // BOM / ZWNBSP.
        case 0xFEFF:
            return true
        // Interlinear annotation, object replacement.
        case 0xFFF9...0xFFFC:
            return true
        // Variation selectors (FE0E/FE0F excluded — handled conditionally).
        case 0xFE00...0xFE0D:
            return true
        // Variation selectors supplement.
        case 0xE0100...0xE01EF:
            return true
        // TAG block ("ASCII smuggling").
        case 0xE0000...0xE007F:
            return true
        default:
            return false
        }
    }

    /// Private-use code points (sanitisation spec §6 step 3), counted separately from the
    /// generic invisible-code-point removal.
    static func isPrivateUse(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0xE000...0xF8FF, 0xF0000...0xFFFFD, 0x100000...0x10FFFD:
            return true
        default:
            return false
        }
    }

    /// The small, explicit set of scripts relevant to the ZWNJ/ZWJ context exception
    /// (sanitisation spec §6.1). Not a general Unicode Script property implementation —
    /// deliberately limited to the scripts the spec names.
    enum ContextScript: Sendable, Equatable {
        case arabic, syriac, thaana, devanagari, bengali, gurmukhi, gujarati, oriya
        case tamil, telugu, kannada, malayalam, sinhala, khmer, myanmar
    }

    /// Looks up `scalar`'s script among the ones the ZWNJ/ZWJ context exception cares
    /// about, `nil` if it belongs to none of them (e.g. Latin, Greek, Cyrillic, digits).
    static func contextScript(of scalar: Unicode.Scalar) -> ContextScript? {
        switch scalar.value {
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF:
            return .arabic
        case 0x0700...0x074F:
            return .syriac
        case 0x0780...0x07BF:
            return .thaana
        case 0x0900...0x097F:
            return .devanagari
        case 0x0980...0x09FF:
            return .bengali
        case 0x0A00...0x0A7F:
            return .gurmukhi
        case 0x0A80...0x0AFF:
            return .gujarati
        case 0x0B00...0x0B7F:
            return .oriya
        case 0x0B80...0x0BFF:
            return .tamil
        case 0x0C00...0x0C7F:
            return .telugu
        case 0x0C80...0x0CFF:
            return .kannada
        case 0x0D00...0x0D7F:
            return .malayalam
        case 0x0D80...0x0DFF:
            return .sinhala
        case 0x1780...0x17FF:
            return .khmer
        case 0x1000...0x109F:
            return .myanmar
        default:
            return nil
        }
    }
}
