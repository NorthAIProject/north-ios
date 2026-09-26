import NorthAPI
import NorthKit
import SwiftUI

/// A few headlines from the feeds chosen on the web; hidden when the ticker is
/// off or empty.
struct NewsSection: View {
    var api: Client = API.shared
    @State private var items: [Components.Schemas.NewsTicker.ItemsPayloadPayload] = []

    var body: some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    NorthCardHeader("News")
                        .padding(.bottom, 4)
                    ForEach(Array(items.prefix(4).enumerated()), id: \.element.url) { index, item in
                        if let url = URL(string: item.url) {
                            if index > 0 { Divider() }
                            Link(destination: url) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.north(.subheadline).weight(.medium))
                                            .foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading)
                                        Text(item.source)
                                            .font(.north(.caption))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 8)
                                .contentShape(.rect)
                            }
                        }
                    }
                }
                .northSurfaceCard(padding: 16)
            }
        }
        .task {
            let ticker = try? await NorthAPI.call { try await api.getNews().ok.body.json }
            items = (ticker?.enabled ?? false) ? (ticker?.items ?? []) : []
        }
    }
}
