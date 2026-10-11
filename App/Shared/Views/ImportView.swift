import SwiftUI

struct ImportView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Text("PDFClean")
                .font(.largeTitle.bold())
                .padding(.top, 20)

            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                    .foregroundStyle(.secondary)
                    .frame(width: 560, height: 180)
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
                                model.beginProcessing()
                            } label: {
                                Label("Open PDF…", systemImage: "folder")
                                    .font(.title3)
                            }
                            .buttonStyle(.borderedProminent)
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
