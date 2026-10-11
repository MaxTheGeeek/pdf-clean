import SwiftUI

struct OptionsView: View {
    @State private var ocrMode = "Automatic"
    @State private var removeHeaders = true
    @State private var removeRepeatedLines = true
    @State private var removeRotatedText = true
    @State private var normalizeLookalikes = true
    @State private var includeTOCPageNumbers = true
    @State private var neutralFileName = false
    @State private var defaultExport = AppModel.ExportFormat.markdown

    var body: some View {
        Form {
            Section("Recognition") {
                Picker("Text recognition", selection: $ocrMode) {
                    Text("Automatic").tag("Automatic")
                    Text("Off").tag("Off")
                    Text("Always").tag("Always")
                }
            }

            Section("Cleaning") {
                Toggle("Remove running headers, footers and page numbers", isOn: $removeHeaders)
                Toggle("Remove repeated lines", isOn: $removeRepeatedLines)
                Toggle("Remove rotated text", isOn: $removeRotatedText)
                Toggle("Normalise look-alike characters", isOn: $normalizeLookalikes)
                Toggle("Include table-of-contents page numbers", isOn: $includeTOCPageNumbers)
            }

            Section("Export") {
                Toggle("Neutral file name", isOn: $neutralFileName)
                Picker("Default export format", selection: $defaultExport) {
                    ForEach(AppModel.ExportFormat.allCases, id: \.self) { format in
                        Text(format.title).tag(format)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 260)
    }
}

#Preview {
    OptionsView()
}
