import CoreGraphics
@preconcurrency import PDFKit

/// Rasterises a page's content (no annotations, no form appearances — sanitisation spec §3.1,
/// T3/T4) to an 8-bit grayscale `GrayRaster`, in **unrotated page space**, for the visibility
/// test.
enum PageRasterizer {

    static func render(page: PDFPage) -> GrayRaster {
        let cropBox = page.bounds(for: .cropBox)
        let scale = CGFloat(Constants.renderScale)
        let width = Int((cropBox.width * scale).rounded(.up))
        let height = Int((cropBox.height * scale).rounded(.up))
        guard width > 0, height > 0 else { return GrayRaster(width: 0, height: 0, pixels: []) }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else {
            return GrayRaster(width: 0, height: 0, pixels: [])
        }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -cropBox.minX, y: -cropBox.minY)
        if let pageRef = page.pageRef {
            context.drawPDFPage(pageRef)
        }

        guard let data = context.data else { return GrayRaster(width: 0, height: 0, pixels: []) }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height)
        return GrayRaster(
            width: width, height: height, pixels: Array(UnsafeBufferPointer(start: buffer, count: width * height)))
    }
}
