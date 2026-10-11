import SwiftUI

struct ProcessingView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.documentName)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("\(model.progressStage) · page \(model.progressPage) of \(model.pageCount)")
                .font(.title3)
                .frame(maxWidth: .infinity, alignment: .leading)

            ProgressView(value: model.progressFraction, total: 1)
                .progressViewStyle(.linear)
                .tint(.blue)

            HStack {
                Spacer()
                Button("Cancel") {
                    model.cancelProcessing()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .frame(width: 420, height: 220)
    }
}

#Preview {
    ProcessingView(model: AppModel())
}
