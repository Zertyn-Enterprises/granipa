import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultLocale") private var defaultLocale = "en-US"
    @AppStorage("echoCancellation") private var echoCancellation = true

    var body: some View {
        Form {
            Picker("Default meeting language", selection: $defaultLocale) {
                Text("English").tag("en-US")
                Text("Español").tag("es-ES")
            }
            Toggle("Echo cancellation (mic)", isOn: $echoCancellation)
            Text("Keep this on if you use speakers; it stops other participants' voices from bleeding into your mic channel.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}
