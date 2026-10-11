import SwiftUI

struct ImportView: View {
    let model: AppModel
    @State private var showFileImporter = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 18) {
            Text("PDFClean")
                .font(.largeTitle.bold())
                .padding(.top, 20)

            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isDropTargeted ? Color.accentColor : .secondary,
                        style: StrokeStyle(lineWidth: 2, dash: [10, 8])
                    )
                    .background(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
                    .frame(width: 560, height: 180)
                    .contentShape(Rectangle())
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let url = urls.first, url.pathExtension.lowercased() == "pdf" else {
                            return false
                        }
                        Task { await model.open(url: url) }
                        return true
                    } isTargeted: { isTargeted in
                        isDropTargeted = isTargeted
                    }
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 44))
                                .foregroundStyle(.blue)
                            Text("Drop a PDF here")
                                .font(.title2.weight(.semibold))
                            Text("or")
                                .foregroundStyle(.secondary)
                            Button {
                                showFileImporter = true
                            } label: {
                                Label("Open PDF…", systemImage: "folder")
                                    .font(.title3)
                            }
                            .buttonStyle(.borderedProminent)
                            .fileImporter(
                                isPresented: $showFileImporter,
                                allowedContentTypes: [.pdf]
                            ) { result in
                                switch result {
                                case .success(let url):
                                    Task { await model.open(url: url) }
                                case .failure(let error):
                                    model.alertTitle = "Open PDF"
                                    model.alertMessage = "Could not open the selected file: \(error.localizedDescription)"
                                    model.screen = .failed
                                }
                            }
                        }
                    }
            }

            Text("Works offline. Nothing leaves this device.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button {
                    model.requirePassword(isOwner: false)
                } label: {
                    Label("Test password flow", systemImage: "lock.shield")
                }
                .buttonStyle(.bordered)

                Button {
                    model.requirePassword(isOwner: true)
                } label: {
                    Label("Test owner-password flow", systemImage: "lock.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .frame(minWidth: 720, minHeight: 420)
    }
}

#Preview {
    ImportView(model: AppModel())
}
