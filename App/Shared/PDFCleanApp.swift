import SwiftUI

/// App entry point. The real flow (Import → Processing → Result) is built in tasks
/// T-050…T-058; see specs/04-ui-spec.md.
@main
struct PDFCleanApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        #endif
    }
}
