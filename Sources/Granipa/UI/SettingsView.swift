import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultLocale") private var defaultLocale = "en-US"

    var body: some View {
        Form {
            Picker("Default meeting language", selection: $defaultLocale) {
                Text("English").tag("en-US")
                Text("Español").tag("es-ES")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}
