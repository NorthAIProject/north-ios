import NorthAPI
import SwiftUI

/// Everything that does not earn a tab: the rest of the web app's sections,
/// and Settings.
struct MoreScreen: View {
    let user: APIUser
    @Environment(AppRouter.self) private var router
    @State private var path: [String] = []

    private struct Section: Identifiable {
        let id: String
        let title: String
        let systemImage: String
    }

    private let growth: [Section] = [
        .init(id: "goals", title: "Goals", systemImage: "target"),
        .init(id: "check-ins", title: "Check-ins", systemImage: "checkmark.circle"),
        .init(id: "reports", title: "Reports", systemImage: "doc.text"),
        .init(id: "memories", title: "Memories", systemImage: "brain"),
        .init(id: "knowledge", title: "Knowledge", systemImage: "books.vertical"),
    ]

    private let life: [Section] = [
        .init(id: "nutrition", title: "Nutrition", systemImage: "fork.knife"),
        .init(id: "care", title: "Care", systemImage: "drop"),
        .init(id: "mind", title: "Mind", systemImage: "sparkles"),
        .init(id: "decisions", title: "Decisions", systemImage: "arrow.triangle.branch"),
    ]

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $path) {
            List {
                sectionRows("Growth", growth)
                sectionRows("Life", life)
                SwiftUI.Section {
                    Button {
                        router.showsSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: String.self) { id in
                if let section = (growth + life).first(where: { $0.id == id }) {
                    destination(for: section)
                }
            }
            .sheet(isPresented: $router.showsSettings) {
                SettingsScreen(user: user)
            }
        }
        // A widget, a shortcut or a nudge naming a section lands on it.
        .onChange(of: router.openSection, initial: true) { _, id in
            guard let id else { return }
            router.openSection = nil
            path = [id]
        }
    }

    @ViewBuilder
    private func destination(for section: Section) -> some View {
        switch section.id {
        case "goals": GoalsScreen()
        case "check-ins": CheckInsScreen()
        case "reports": ReportsScreen()
        case "memories": MemoriesScreen()
        case "knowledge": KnowledgeScreen()
        case "nutrition": NutritionScreen()
        case "care": CareScreen()
        case "mind": JournalScreen()
        case "decisions": DecisionsScreen()
        default: EmptyView()
        }
    }

    private func sectionRows(_ header: String, _ sections: [Section]) -> some View {
        SwiftUI.Section(header) {
            ForEach(sections) { section in
                NavigationLink(value: section.id) {
                    Label(section.title, systemImage: section.systemImage)
                }
            }
        }
    }
}
