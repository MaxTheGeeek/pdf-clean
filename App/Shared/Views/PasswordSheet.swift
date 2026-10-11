import SwiftUI

struct PasswordSheet: View {
    let model: AppModel
    @State private var password = ""

    var body: some View {
        VStack(spacing: 16) {
            Text(model.passwordPromptTitle)
                .font(.title2.weight(.semibold))

            Text(model.passwordPromptDetail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack(spacing: 12) {
                Button("Cancel") {
                    model.startImport()
                }
                .buttonStyle(.bordered)

                Button("Unlock") {
                    model.unlockPassword()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 420)
    }
}

#Preview {
    PasswordSheet(model: AppModel())
}
