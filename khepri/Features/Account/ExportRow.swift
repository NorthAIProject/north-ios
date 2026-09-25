import NorthAPI
import OpenAPIRuntime
import SwiftUI

/// Everything in the account as a zip, handed to the share sheet: Files,
/// AirDrop, mail. The archive is written to a temporary file first, so the
/// sheet can share it by URL.
struct ExportRow: View {
    var api: Client = API.shared
    @State private var file: URL?
    @State private var working = false
    @State private var error: String?

    var body: some View {
        Group {
            if let file {
                ShareLink(item: file) { Label("Share Your Export", systemImage: "square.and.arrow.up") }
            } else {
                Button {
                    Task { await export() }
                } label: {
                    Label(working ? "Preparing…" : "Export My Data", systemImage: "archivebox")
                }
                .disabled(working)
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private func export() async {
        working = true
        defer { working = false }
        do {
            let body = try await NorthAPI.call { try await api.exportAccount().ok.body.applicationZip }
            let url = FileManager.default.temporaryDirectory.appending(path: "khepri-export.zip")
            try? FileManager.default.removeItem(at: url)
            FileManager.default.createFile(atPath: url.path(), contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            for try await chunk in body {
                try handle.write(contentsOf: Data(chunk))
            }
            file = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
