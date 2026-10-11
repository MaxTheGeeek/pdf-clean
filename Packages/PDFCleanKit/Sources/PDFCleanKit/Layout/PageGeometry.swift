import CoreGraphics

/// Converts rectangles between unrotated PDF page space and the *display space* used for all
/// layout (tech spec §5). Display space has its origin at the crop box's top-left, the y-axis
/// points downward, and the page's `/Rotate` value is applied. Every part of the pipeline except
/// the raster visibility test lives in display space.
///
/// Page space (the PDF default): origin at the (possibly offset) crop box's bottom-left, y upward,
/// no rotation. The two spaces are related by an offset, a y-flip, and a 90°-stepped rotation.
enum PageGeometry {

    /// Normalises a `/Rotate` value to one of 0, 90, 180 or 270. PDF only defines those four
    /// values; anything else is treated as no rotation, matching PDFKit's behaviour.
    static func normalizedRotation(_ rotation: Int) -> Int {
        var r = rotation % 360
        if r < 0 { r += 360 }
        switch r {
        case 90, 180, 270: return r
        default: return 0
        }
    }

    /// The display-space size of a page given its unrotated crop box and `/Rotate` value.
    /// A 90° or 270° rotation swaps the width and height.
    static func displaySize(cropBox: CGRect, rotation: Int) -> CGSize {
        switch normalizedRotation(rotation) {
        case 90, 270:
            return CGSize(width: cropBox.height, height: cropBox.width)
        default:
            return CGSize(width: cropBox.width, height: cropBox.height)
        }
    }

    /// Maps each corner of a page-space rectangle into display space and returns the bounding box
    /// of those four corners (an axis-aligned rect is mapped corner-by-corner because a 90°/270°
    /// rotation swaps the two axes). Returns `CGRect.null` for a degenerate input.
    static func pageToDisplay(_ rect: CGRect, cropBox: CGRect, rotation: Int) -> CGRect {
        guard !rect.isNull, cropBox.width > 0, cropBox.height > 0 else { return .null }
        let rotation = normalizedRotation(rotation)
        let mapped = corners(of: rect).map { self.mapped($0, forward: true, cropBox: cropBox, rotation: rotation) }
        return boundingBox(of: mapped)
    }

    /// Inverse of `pageToDisplay`: maps a display-space rectangle back into page space.
    static func displayToPage(_ rect: CGRect, cropBox: CGRect, rotation: Int) -> CGRect {
        guard !rect.isNull, cropBox.width > 0, cropBox.height > 0 else { return .null }
        let rotation = normalizedRotation(rotation)
        let mapped = corners(of: rect).map { self.mapped($0, forward: false, cropBox: cropBox, rotation: rotation) }
        return boundingBox(of: mapped)
    }

    // MARK: - Private helpers

    /// Maps a single point between the two spaces. `forward == true` goes page → display.
    private static func mapped(_ p: CGPoint, forward: Bool, cropBox: CGRect, rotation: Int) -> CGPoint {
        let w = cropBox.width
        let h = cropBox.height
        guard w > 0, h > 0 else { return p }
        if forward {
            let u = (p.x - cropBox.minX) / w
            let v = (p.y - cropBox.minY) / h
            switch rotation {
            case 0: return CGPoint(x: u * w, y: (1 - v) * h)
            case 180: return CGPoint(x: (1 - u) * w, y: v * h)
            case 90: return CGPoint(x: v * h, y: u * w)
            default: return CGPoint(x: (1 - v) * h, y: (1 - u) * w)  // 270
            }
        } else {
            let u: CGFloat
            let v: CGFloat
            switch rotation {
            case 0: u = p.x / w; v = 1 - p.y / h
            case 180: u = 1 - p.x / w; v = p.y / h
            case 90: v = p.x / h; u = p.y / w
            default: v = 1 - p.x / h; u = 1 - p.y / w  // 270
            }
            return CGPoint(x: cropBox.minX + u * w, y: cropBox.minY + v * h)
        }
    }

    private static func corners(of rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ]
    }

    private static func boundingBox(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
