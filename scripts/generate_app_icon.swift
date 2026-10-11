import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fileManager = FileManager.default
try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
}

func drawIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "PDFCleanIcon", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.shouldAntialias = true
    let scale = CGFloat(size) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)

    color(0.075, 0.22, 0.22).setFill()
    NSBezierPath(roundedRect: NSRect(x: 24, y: 24, width: 976, height: 976), xRadius: 220, yRadius: 220).fill()

    let page = NSBezierPath()
    page.move(to: NSPoint(x: 214, y: 112))
    page.line(to: NSPoint(x: 214, y: 884))
    page.line(to: NSPoint(x: 624, y: 884))
    page.line(to: NSPoint(x: 810, y: 698))
    page.line(to: NSPoint(x: 810, y: 112))
    page.close()
    let shadow = NSShadow()
    shadow.shadowColor = color(0.015, 0.08, 0.085).withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    color(0.97, 0.96, 0.91).setFill()
    page.fill()
    NSShadow().set()

    let fold = NSBezierPath()
    fold.move(to: NSPoint(x: 624, y: 884))
    fold.line(to: NSPoint(x: 624, y: 698))
    fold.line(to: NSPoint(x: 810, y: 698))
    fold.close()
    color(0.83, 0.84, 0.79).setFill()
    fold.fill()

    color(0.86, 0.25, 0.16).setFill()
    NSBezierPath(roundedRect: NSRect(x: 282, y: 542, width: 462, height: 150), xRadius: 34, yRadius: 34).fill()
    let title = NSAttributedString(
        string: "PDF",
        attributes: [
            .font: NSFont.systemFont(ofSize: 108, weight: .black),
            .foregroundColor: color(1, 0.98, 0.94),
        ]
    )
    title.draw(at: NSPoint(x: 334, y: 557))

    color(0.15, 0.24, 0.23).setStroke()
    for (y, width) in [(448, 370), (374, 438), (300, 286)] {
        let line = NSBezierPath()
        line.lineWidth = 19
        line.lineCapStyle = .round
        line.move(to: NSPoint(x: 294, y: y))
        line.line(to: NSPoint(x: 294 + width, y: y))
        line.stroke()
    }

    color(0.075, 0.22, 0.22).setFill()
    NSBezierPath(ovalIn: NSRect(x: 620, y: 154, width: 126, height: 126)).fill()
    let check = NSBezierPath()
    check.lineWidth = 17
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    check.move(to: NSPoint(x: 650, y: 214))
    check.line(to: NSPoint(x: 675, y: 188))
    check.line(to: NSPoint(x: 720, y: 242))
    color(0.36, 0.83, 0.68).setStroke()
    check.stroke()

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PDFCleanIcon", code: 2)
    }
    return data
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    let data = try drawIcon(size: size)
    let destination = outputDirectory.appendingPathComponent("AppIcon-\(size).png")
    try data.write(to: destination)
}
