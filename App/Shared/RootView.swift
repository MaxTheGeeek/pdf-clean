import PDFCleanKit
import SwiftUI

/// Placeholder root view; replaced in T-051 (ImportView) and T-050 (AppModel state switch).
struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .accessibilityHidden(true)
            Text("PDFClean")
                .font(.largeTitle.bold())
            Text("Works offline. Nothing leaves this device.")
                .foregroundStyle(.secondary)
            Text(verbatim: "Core \(PDFCleanKit.version)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(minWidth: 320, minHeight: 240)
    }
}

#Preview {
    RootView()
}
