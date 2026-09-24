import NorthAPI
import SwiftUI

/// Everything that does not earn a tab: the rest of the web app's sections,
/// and Settings.
struct MoreScreen: View {
    let user: APIUser
    @Environment(AppRouter.self) private var router

    private struct Section: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let phase: Int
        let summary: String
    }

    private let growth: [Section] = [
        .init(id: "goals", title: "Goals", systemImage: "target", phase: 5, summary: "Goals, milestones and the updates that move them."),
        .init(id: "check-ins", title: "Check-ins", systemImage: "checkmark.circle", phase: 5, summary: "How you are arriving, day by day."),
        .init(id: "reports", title: "Reports", systemImage: "doc.text", phase: 5, summary: "Weekly reviews your coach writes."),
        .init(id: "memories", title: "Memories", systemImage: "brain", phase: 5, summary: "What your coach remembers, and what it should forget."),
        .init(id: "knowledge", title: "Knowledge", systemImage: "books.vertical", phase: 5, summary: "Notes and documents your coach can search."),
    ]

    private let life: [Section] = [
        .init(id: "nutrition", title: "Nutrition", systemImage: "fork.knife", phase: 6, summary: "Meal plans and what you ate."),
        .init(id: "care", title: "Care", systemImage: "drop", phase: 6, summary: "Water, sleep, habits and reminders."),
        .init(id: "mind", title: "Mind", systemImage: "sparkles", phase: 6, summary: "Journal and reflection."),
        .init(id: "decisions", title: "Decisions", systemImage: "arrow.triangle.branch", phase: 6, summary: "Think a choice through with your coach."),
    ]

    var body: some View {
        @Bindable var router = router
        NavigationStack {
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
            .sheet(isPresented: $router.showsSettings) {
                SettingsScreen(user: user)
            }
        }
    }

    private func sectionRows(_ header: String, _ sections: [Section]) -> some View {
        SwiftUI.Section(header) {
            ForEach(sections) { section in
                NavigationLink {
                    PlaceholderScreen(title: section.title, systemImage: section.systemImage, phase: section.phase, summary: section.summary).content
                } label: {
                    Label(section.title, systemImage: section.systemImage)
                }
            }
        }
    }
}
