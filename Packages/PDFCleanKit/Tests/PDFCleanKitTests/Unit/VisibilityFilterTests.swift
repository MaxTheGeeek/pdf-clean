import CoreGraphics
import Foundation
import Testing

@testable import PDFCleanKit

/// TC-U15 (T-033): `VisibilityFilter` on synthetic rasters — black ink is visible, an all-white
/// region is hidden, a neighbour's descender bleeding into a region is masked out (tight
/// case), a fully overlapped region falls back to the whole box, and dark background with
/// light text is visible (the ink test is symmetric).
@Suite("VisibilityFilter")
struct VisibilityFilterTests {

    @Test("a region with a black ink patch on a white background is visible")
    func blackInkOnWhiteIsVisible() {
        var raster = whiteRaster(width: 10, height: 10)
        paint(&raster, x: 3, y: 3, width: 3, height: 3, value: 0)  // 9% ink
        let result = VisibilityFilter.classify(raster: raster, regions: [CGRect(x: 0, y: 0, width: 10, height: 10)])
        #expect(result == [true])
    }

    @Test("an all-white region is hidden")
    func allWhiteIsHidden() {
        let raster = whiteRaster(width: 10, height: 10)
        let result = VisibilityFilter.classify(raster: raster, regions: [CGRect(x: 0, y: 0, width: 10, height: 10)])
        #expect(result == [false])
    }

    @Test("a neighbour's descender bleeding into a region is masked out of it")
    func neighbourDescenderMaskedOut() {
        var raster = whiteRaster(width: 10, height: 20)
        // Dark strip at rows 8-9 of the hidden word's own region: a descender from the line
        // below bleeding upward. Without exclusion this would read as 20% ink (visible).
        paint(&raster, x: 0, y: 8, width: 10, height: 2, value: 0)
        let hiddenRegion = CGRect(x: 0, y: 0, width: 10, height: 10)
        // Neighbour's own box starts right where the dark strip is (y: 10...20); padded by
        // 0.25 x its height (2.5) it reaches up to y = 7.5, covering the dark strip.
        let neighbourRegion = CGRect(x: 0, y: 10, width: 10, height: 10)
        let result = VisibilityFilter.classify(raster: raster, regions: [hiddenRegion, neighbourRegion])
        #expect(result[0] == false)
    }

    @Test("a fully overlapped region falls back to measuring the whole box")
    func fullyOverlappedFallsBackToFullBox() {
        var raster = whiteRaster(width: 10, height: 10)
        paint(&raster, x: 3, y: 3, width: 3, height: 3, value: 0)
        let region = CGRect(x: 0, y: 0, width: 10, height: 10)
        // An identical "other" word box covers the whole region: the exclusive-area mask
        // would exclude 100% of it, so the fallback must measure the full box anyway and
        // still find the ink patch.
        let result = VisibilityFilter.classify(raster: raster, regions: [region, region])
        #expect(result[0] == true)
    }

    @Test("light ink on a dark background is visible (the ink test is symmetric)")
    func lightInkOnDarkBackgroundIsVisible() {
        var raster = GrayRaster(width: 10, height: 10, pixels: [UInt8](repeating: 0, count: 100))
        paint(&raster, x: 3, y: 3, width: 3, height: 3, value: 255)  // 9% light ink on black
        let result = VisibilityFilter.classify(raster: raster, regions: [CGRect(x: 0, y: 0, width: 10, height: 10)])
        #expect(result == [true])
    }

    @Test("an empty raster yields no visible words")
    func emptyRaster() {
        let raster = GrayRaster(width: 0, height: 0, pixels: [])
        let result = VisibilityFilter.classify(raster: raster, regions: [CGRect(x: 0, y: 0, width: 10, height: 10)])
        #expect(result == [false])
    }

    // MARK: - Fixtures

    func whiteRaster(width: Int, height: Int) -> GrayRaster {
        GrayRaster(width: width, height: height, pixels: [UInt8](repeating: 255, count: width * height))
    }

    func paint(_ raster: inout GrayRaster, x: Int, y: Int, width: Int, height: Int, value: UInt8) {
        for row in y..<(y + height) {
            for col in x..<(x + width) {
                raster.pixels[row * raster.width + col] = value
            }
        }
    }
}
