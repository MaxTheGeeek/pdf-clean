// swift-tools-version: 6.0
// PDFCleanKit — offline PDF → clean structured text. Apple frameworks only (constitution P1).
import PackageDescription

let package = Package(
    name: "PDFCleanKit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "PDFCleanKit", targets: ["PDFCleanKit"]),
        .executable(name: "pdfclean", targets: ["pdfclean"]),
    ],
    // No dependencies by design. Do not add any (see specs/00-constitution.md, P1).
    dependencies: [],
    targets: [
        .target(
            name: "PDFCleanKit",
            path: "Sources/PDFCleanKit"
        ),
        .executableTarget(
            name: "pdfclean",
            dependencies: ["PDFCleanKit"],
            path: "Sources/pdfclean"
        ),
        .testTarget(
            name: "PDFCleanKitTests",
            dependencies: ["PDFCleanKit"],
            path: "Tests/PDFCleanKitTests",
            resources: [
                .copy("Fixtures"),
                .copy("Golden"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
