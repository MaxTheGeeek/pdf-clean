import PDFCleanKit
import SwiftUI

struct RootView: View {
    @State private var appModel = AppModel()

    var body: some View {
        Group {
            switch appModel.screen {
            case .importView:
                ImportView(model: appModel)
            case .awaitingPassword:
                PasswordSheet(model: appModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.thinMaterial)
            case .processing:
                ProcessingView(model: appModel)
            case .result:
                ResultView(model: appModel)
            case .failed:
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    Text("The file could not be processed")
                        .font(.title2.bold())
                    if !appModel.alertMessage.isEmpty {
                        Text(appModel.alertMessage)
                            .foregroundStyle(.secondary)
                    }
                    Button("Choose Another File") {
                        appModel.startImport()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Group {
                #if os(macOS)
                    Color(nsColor: .windowBackgroundColor)
                #else
                    Color(uiColor: .systemBackground)
                #endif
            }
        )
    }
}

#Preview {
    RootView()
}
