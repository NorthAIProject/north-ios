import NorthAPI
import SwiftUI

/// Everything one person has earned, from their profile response.
struct ProfileAwardsScreen: View {
    let name: String
    let awards: [Award]

    @State private var shown: Award?

    var body: some View {
        List(awards, id: \.id) { award in
            Button { shown = award } label: {
                AwardRow(row: AwardsModel.Row(award: award, isNew: false))
            }
            .foregroundStyle(.primary)
        }
        .navigationTitle("\(name)'s Awards")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shown) { award in
            AwardDetailSheet(award: award)
                .presentationDetents([.medium])
        }
    }
}
