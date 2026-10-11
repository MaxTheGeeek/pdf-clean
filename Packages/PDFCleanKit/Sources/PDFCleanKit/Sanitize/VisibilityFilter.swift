import CoreGraphics

/// An 8-bit grayscale raster, row 0 = the **top** row (sanitisation spec §3.1). A pure value
/// type so the ink computation in `VisibilityFilter` is unit-testable without PDFKit.
struct GrayRaster: Equatable, Sendable {
    var width: Int
    var height: Int
    /// Row-major, length `width × height`.
    var pixels: [UInt8]

    /// Out-of-bounds reads return white (255) — the raster is filled white before any content
    /// is drawn, so this matches what a genuinely empty/overflowing region would sample.
    func pixel(x: Int, y: Int) -> UInt8 {
        guard x >= 0, x < width, y >= 0, y < height else { return 255 }
        return pixels[y * width + x]
    }
}

/// Decides which words are actually visible, by rasterising the page and measuring ink under
/// each word's exclusive area (sanitisation spec §3; reference implementation:
/// `scripts/reference/visibility_reference.py`). Pure, side-effect free.
enum VisibilityFilter {

    /// Classifies each of `regions` (pixel space, row 0 = top, one per word, same order) as
    /// visible (`true`) or hidden (`false`) against `raster`.
    static func classify(raster: GrayRaster, regions: [CGRect]) -> [Bool] {
        guard raster.width > 0, raster.height > 0 else { return regions.map { _ in false } }
        return regions.enumerated().map { i, region in
            isVisible(region: region, index: i, allRegions: regions, raster: raster)
        }
    }

    /// Converts each word's `pageBox` (unrotated page space) to pixel space via `cropBox` and
    /// `Constants.renderScale`, then classifies.
    static func classify(words: [Word], raster: GrayRaster, cropBox: CGRect) -> [Bool] {
        let regions = words.map {
            pixelRect(
                for: $0.pageBox, cropBox: cropBox, scale: CGFloat(Constants.renderScale), rasterHeight: raster.height)
        }
        return classify(raster: raster, regions: regions)
    }

    // MARK: - Per-word decision (spec §3.2)

    private static func isVisible(region: CGRect, index: Int, allRegions: [CGRect], raster: GrayRaster) -> Bool {
        let bounds = integerBounds(of: region, raster: raster)
        guard bounds.width > 0, bounds.height > 0 else { return false }

        var included = [Bool](repeating: true, count: bounds.width * bounds.height)
        var includedCount = included.count
        for (j, other) in allRegions.enumerated() where j != index {
            let pad = CGFloat(Constants.neighbourPad) * other.height
            let expanded = other.insetBy(dx: 0, dy: -pad)
            includedCount -= excludeOverlap(expanded, from: bounds, raster: raster, in: &included)
        }

        let exclusiveShare = Double(includedCount) / Double(included.count)
        let measured: [UInt8]
        if exclusiveShare >= Constants.minExclusiveShare {
            measured = pixels(of: bounds, raster: raster).enumerated().compactMap {
                included[$0.offset] ? $0.element : nil
            }
        } else {
            measured = pixels(of: bounds, raster: raster)
        }
        guard !measured.isEmpty else { return false }

        let background = Int(medianBorderLuminance(of: bounds, raster: raster))
        let inkCount = measured.filter { abs(Int($0) - background) > Constants.inkDelta }.count
        let inkFraction = Double(inkCount) / Double(measured.count)
        return inkFraction >= Constants.minInkFraction
    }

    // MARK: - Pixel-grid helpers

    private struct IntBounds { var x0: Int; var y0: Int; var width: Int; var height: Int }

    private static func integerBounds(of rect: CGRect, raster: GrayRaster) -> IntBounds {
        let x0 = max(0, min(raster.width, Int(rect.minX)))
        let x1 = max(0, min(raster.width, Int(rect.maxX)))
        let y0 = max(0, min(raster.height, Int(rect.minY)))
        let y1 = max(0, min(raster.height, Int(rect.maxY)))
        return IntBounds(x0: x0, y0: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    private static func pixels(of bounds: IntBounds, raster: GrayRaster) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(bounds.width * bounds.height)
        for y in bounds.y0..<(bounds.y0 + bounds.height) {
            for x in bounds.x0..<(bounds.x0 + bounds.width) {
                result.append(raster.pixel(x: x, y: y))
            }
        }
        return result
    }

    /// Marks pixels of `bounds` that fall inside `otherRegion` as excluded (`false`) in
    /// `included` (indexed the same way `pixels(of:raster:)` enumerates `bounds`). Returns how
    /// many pixels were newly excluded.
    private static func excludeOverlap(
        _ otherRegion: CGRect, from bounds: IntBounds, raster: GrayRaster, in included: inout [Bool]
    ) -> Int {
        let other = integerBounds(of: otherRegion, raster: raster)
        let x0 = max(bounds.x0, other.x0)
        let x1 = min(bounds.x0 + bounds.width, other.x0 + other.width)
        let y0 = max(bounds.y0, other.y0)
        let y1 = min(bounds.y0 + bounds.height, other.y0 + other.height)
        guard x1 > x0, y1 > y0 else { return 0 }
        var excludedNow = 0
        for y in y0..<y1 {
            let rowBase = (y - bounds.y0) * bounds.width
            for x in x0..<x1 {
                let idx = rowBase + (x - bounds.x0)
                if included[idx] {
                    included[idx] = false
                    excludedNow += 1
                }
            }
        }
        return excludedNow
    }

    /// Median of the region's border pixels (top row + bottom row + left column + right
    /// column — corners counted twice, matching the reference implementation exactly).
    private static func medianBorderLuminance(of bounds: IntBounds, raster: GrayRaster) -> UInt8 {
        var values: [Int] = []
        let xEnd = bounds.x0 + bounds.width - 1
        let yEnd = bounds.y0 + bounds.height - 1
        for x in bounds.x0...xEnd {
            values.append(Int(raster.pixel(x: x, y: bounds.y0)))
            values.append(Int(raster.pixel(x: x, y: yEnd)))
        }
        for y in bounds.y0...yEnd {
            values.append(Int(raster.pixel(x: bounds.x0, y: y)))
            values.append(Int(raster.pixel(x: xEnd, y: y)))
        }
        values.sort()
        let n = values.count
        guard n > 0 else { return 255 }
        if n % 2 == 1 { return UInt8(values[n / 2]) }
        return UInt8((values[n / 2 - 1] + values[n / 2]) / 2)
    }

    // MARK: - Page space -> pixel space (row 0 = top)

    /// `pageRect` is in unrotated page space (origin bottom-left, y up). The raster's row 0 is
    /// its top row, so this flips vertically — see `PageRasterizer`.
    private static func pixelRect(for pageRect: CGRect, cropBox: CGRect, scale: CGFloat, rasterHeight: Int) -> CGRect {
        let x0 = (pageRect.minX - cropBox.minX) * scale
        let x1 = (pageRect.maxX - cropBox.minX) * scale
        let yBottom0 = (pageRect.minY - cropBox.minY) * scale
        let yBottom1 = (pageRect.maxY - cropBox.minY) * scale
        let yTop0 = CGFloat(rasterHeight) - yBottom1
        let yTop1 = CGFloat(rasterHeight) - yBottom0
        return CGRect(x: x0, y: yTop0, width: x1 - x0, height: yTop1 - yTop0)
    }
}
