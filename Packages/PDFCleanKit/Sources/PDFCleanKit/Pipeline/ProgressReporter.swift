import Foundation

/// The fixed stage budget for `ExtractionPipeline`'s progress fractions (tech spec §7):
/// opening 2%, pages 80% (split per page), layout 10%, cleaning 8%.
enum ProgressReporter {
    static let openingFraction = 0.02
    static let pagesFraction = 0.80
    static let layoutFraction = 0.10
    static let cleaningFraction = 0.08

    static let afterOpening = openingFraction
    static let afterPages = afterOpening + pagesFraction
    static let afterLayout = afterPages + layoutFraction
    static let afterCleaning = afterLayout + cleaningFraction

    /// Fraction completed while about to read page `pageIndex` (0-based) of `pageCount`.
    static func pagesProgress(pageIndex: Int, pageCount: Int) -> Double {
        guard pageCount > 0 else { return afterOpening }
        return afterOpening + pagesFraction * Double(pageIndex) / Double(pageCount)
    }
}
