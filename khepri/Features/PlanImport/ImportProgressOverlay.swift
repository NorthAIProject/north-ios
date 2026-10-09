import SwiftUI

/// The card shown over an import sheet while a file is read or a plan saved.
struct ImportProgressOverlay: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title).font(.headline)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
    }
}
