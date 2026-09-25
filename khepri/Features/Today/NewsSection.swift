import NorthAPI
import SwiftUI

/// A few headlines from the feeds chosen on the web; hidden when the ticker is
/// off or empty.
struct NewsSection: View {
    var api: Client = API.shared
    @State private var items: [Components.Schemas.NewsTicker.ItemsPayloadPayload] = []

    var body: some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("NEWS").font(.caption.weight(.medium)).tracking(1.5).foregroundStyle(.secondary)
                    ForEach(items.prefix(4), id: \.url) { item in
                        if let url = URL(string: item.url) {
                            Link(destination: url) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                    Text(item.source).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            let ticker = try? await NorthAPI.call { try await api.getNews().ok.body.json }
            items = (ticker?.enabled ?? false) ? (ticker?.items ?? []) : []
        }
    }
}
