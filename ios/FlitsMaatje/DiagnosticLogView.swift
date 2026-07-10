import SwiftUI

struct DiagnosticLogView: View {
    @ObservedObject private var store = AppLogStore.shared

    var body: some View {
        List {
            Section {
                ShareLink(item: AppLogger.logFileURL()) {
                    Label("Logbestand delen", systemImage: "square.and.arrow.up")
                }

                Button {
                    AppLogger.uploadLogFile(reason: "manual")
                } label: {
                    Label("Log naar server sturen", systemImage: "icloud.and.arrow.up")
                }

                Button(role: .destructive) {
                    store.clear()
                } label: {
                    Label("Log wissen", systemImage: "trash")
                }
            } footer: {
                Text("Logs worden automatisch naar de server gestuurd bij opstarten en crashes. Je kunt ze ook handmatig delen.")
            }

            Section("Recent") {
                if store.lines.isEmpty {
                    Text("Nog geen logregels.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(store.lines.reversed().enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("Diagnostiek")
        .onAppear {
            store.reload()
        }
    }
}
