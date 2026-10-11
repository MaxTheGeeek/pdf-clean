import SwiftUI

struct ResultView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Format", selection: $model.selectedFormat) {
                    ForEach(AppModel.ExportFormat.allCases, id: \.self) { format in
                        Text(format.title).tag(format)
                    }
                }
                .frame(width: 170)

                Toggle("Show source", isOn: $model.showSource)
                    .toggleStyle(.switch)

                Spacer()

                Button("New") {
                    model.newDocument()
                }

                Button("Save…") {
                    model.completeProcessing()
                }
                .keyboardShortcut("s")
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Divider()

            HStack(alignment: .top, spacing: 0) {
                List(model.outlineEntries, id: \.self) { entry in
                    Text(entry)
                        .padding(.vertical, 4)
                }
                .frame(width: 240)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(model.resultTitle)
                            .font(.largeTitle)
                            .padding(.bottom, 8)

                        Text(model.resultPreview)
                            .font(.body)
                            .foregroundStyle(.primary)

                        if model.showSource {
                            Text(
                                "# Quarterly Infrastructure Report\n\nThis report summarises the migration path and the operational risk review."
                            )
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(28)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Label("Verified clean", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.headline)

                    ForEach(model.reportSummary.sourceInventory, id: \.self) { item in
                        Text(item)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Identifiers")
                            .font(.headline)
                        ForEach(model.reportSummary.identifiers, id: \.self) { identifier in
                            Label(identifier, systemImage: "square.and.pencil")
                                .font(.caption)
                        }
                    }
                }
                .frame(width: 280)
                .padding(16)
            }
        }
        .frame(minWidth: 960, minHeight: 620)
    }
}

#Preview {
    ResultView(model: AppModel())
}
