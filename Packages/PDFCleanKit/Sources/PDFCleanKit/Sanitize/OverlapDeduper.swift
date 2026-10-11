import CoreGraphics

/// Collapses duplicate overlapping words — e.g. fake-bold text drawn twice (sanitisation spec
/// §4). Two words on the same page with equal text (after NFC) whose display-space boxes have
/// IoU >= `duplicateIoU` are duplicates; the first in content order is kept. Pure, side-effect
/// free; call once per page.
enum OverlapDeduper {

    struct Result: Equatable, Sendable {
        var words: [Word]
        var removedOverlappingDuplicates: Int = 0
    }

    static func dedupe(words: [Word]) -> Result {
        var kept: [Word] = []
        var removed = 0
        for word in words {
            let normalizedText = word.text.precomposedStringWithCanonicalMapping
            let isDuplicate = kept.contains { candidate in
                candidate.text.precomposedStringWithCanonicalMapping == normalizedText
                    && iou(candidate.box, word.box) >= Constants.duplicateIoU
            }
            if isDuplicate {
                removed += 1
            } else {
                kept.append(word)
            }
        }
        return Result(words: kept, removedOverlappingDuplicates: removed)
    }

    private static func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let intersection = a.intersection(b)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return Double(intersectionArea / unionArea)
    }
}
