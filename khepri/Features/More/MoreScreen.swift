import NorthAPI
import SwiftUI

/// Everything that does not earn a tab: the rest of the web app's sections,
/// and Settings.
struct MoreScreen: View {
    let user: APIUser
    @Environment(AppRouter.self) private var router
    @Environment(CrewUnread.self) private var crewUnread
    @State private var path: [MoreRoute] = []
    private let crewsService: CrewsServicing = CrewsService()

    private struct Section: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let systemImage: String
    }

    private let growth: [Section] = [
        .init(id: "daily", title: "Daily Post", systemImage: "newspaper"),
        .init(id: "goals", title: "Goals", systemImage: "target"),
        .init(id: "check-ins", title: "Check-ins", systemImage: "checkmark.circle"),
        .init(id: "progress-check", title: "Progress check", systemImage: "ruler"),
        .init(id: "reports", title: "Reports", systemImage: "doc.text"),
        .init(id: "memories", title: "Memories", systemImage: "brain"),
        .init(id: "knowledge", title: "Knowledge", systemImage: "books.vertical"),
        .init(id: "friends", title: "Friends", systemImage: "person.2"),
        .init(id: "crews", title: "Crews", systemImage: "flag.2.crossed"),
        .init(id: "inbox", title: "Inbox", systemImage: "tray"),
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
                SwiftUI.Section {
                    // A sheet rather than a pushed screen: the Sunday nudge
                    // opens the same flow over whatever tab is showing.
                    Button {
                        router.open(.weeklyReview)
                    } label: {
                        Label("Plan the Week", systemImage: "calendar.badge.checkmark")
                    }
                    .foregroundStyle(.primary)
                }
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
            .navigationDestination(for: MoreRoute.self) { route in
                switch route {
                case .section(let id):
                    if let section = (growth + life).first(where: { $0.id == id }) {
                        destination(for: section)
                    }
                case .crew(let opened):
                    // Each opening is its own space, with its own live stream,
                    // never an earlier one's state. (An id on the destination
                    // itself left an old space showing.)
                    ZStack {
                        CrewSpaceScreen(
                            crew: opened.crew, meID: user.id, crews: crewsService, firstChannelID: opened.channelID
                        )
                            .id(opened)
                    }
                }
            }
            .sheet(isPresented: $router.showsSettings) {
                SettingsScreen(user: user)
            }
        }
        // A crew push or link. Handled here, at the stack's root, and not by
        // the Crews list under an open space: a covered screen reacting to
        // it made the stack drop the space above it.
        .onChange(of: router.openCrew, initial: true) { _, route in
            guard let route else { return }
            router.openCrew = nil
            Task { await follow(route) }
        }
        // A widget, a shortcut or a nudge naming a section lands on it.
        .onChange(of: router.openSection, initial: true) { _, id in
            guard let id else { return }
            router.openSection = nil
            let next = MorePath.opening(section: id, in: path)
            if next != path { path = next }
        }
    }

    /// The open crew moves to the linked channel; any other crew's space
    /// replaces it. A crew you are not in (any more) leaves the list showing.
    private func follow(_ route: CrewRoute) async {
        switch CrewLinkLanding(route, openCrewID: MorePath.openCrewID(in: path)) {
        case .switchChannel:
            router.crewChannelRequest = route
        case .openSpace:
            let crews = (try? await crewsService.crews()) ?? []
            guard let crew = crews.first(where: { $0.id.lowercased() == route.crewID }) else { return }
            if MorePath.openCrewID(in: path) != nil {
                // Swapping the top of the stack in place is not reliable: the
                // stack often kept showing the old space. Close it without
                // animation, then push the new one.
                var closing = Transaction()
                closing.disablesAnimations = true
                withTransaction(closing) { path = MorePath.closingCrew(in: path) }
                try? await Task.sleep(for: .milliseconds(100))
            }
            // The channel rides on the path value, not on router state.
            path = MorePath.opening(OpenedCrew(crew: crew, channelID: route.channelID), in: path)
        }
    }

    @ViewBuilder
    private func destination(for section: Section) -> some View {
        switch section.id {
        case "goals": GoalsScreen()
        case "check-ins": CheckInsScreen()
        case "progress-check": ProgressCheckScreen()
        case "reports": ReportsScreen()
        case "memories": MemoriesScreen()
        case "knowledge": KnowledgeScreen()
        case "nutrition": NutritionScreen()
        case "care": CareScreen()
        case "mind": JournalScreen()
        case "decisions": DecisionsScreen()
        case "friends": FriendsScreen()
        case "crews": CrewsScreen(path: $path)
        case "inbox": InboxScreen()
        case "daily": DailyPostScreen()
        default: EmptyView()
        }
    }

    private func sectionRows(_ header: LocalizedStringKey, _ sections: [Section]) -> some View {
        SwiftUI.Section(header) {
            ForEach(sections) { section in
                NavigationLink(value: MoreRoute.section(section.id)) {
                    Label(section.title, systemImage: section.systemImage)
                }
                .badge(section.id == "crews" ? crewUnread.total : 0)
            }
        }
    }
}

/// A screen on the More tab's stack: a section, or one crew's space over
/// Crews. Crew spaces live on the path itself rather than in a nested
/// `navigationDestination(item:)`: a path-bound stack drops item-pushed
/// screens whenever it updates (a link setting the tab and section is
/// enough), which left a stale space on screen and pushed a second one under
/// it.
enum MoreRoute: Hashable {
    case section(String)
    case crew(OpenedCrew)
}

/// How links and taps change the More stack.
nonisolated enum MorePath {
    /// A section link opens that section alone, unless the stack already
    /// starts there: a crew link names Crews too, and must not pop the crew
    /// space it is about to switch.
    static func opening(section id: String, in path: [MoreRoute]) -> [MoreRoute] {
        path.first == .section(id) ? path : [.section(id)]
    }

    /// The crew whose space is on top of the stack, lowercased.
    static func openCrewID(in path: [MoreRoute]) -> String? {
        guard case .crew(let opened) = path.last else { return nil }
        return opened.crew.id.lowercased()
    }

    /// The stack with any crew space closed: Crews, if it was open.
    static func closingCrew(in path: [MoreRoute]) -> [MoreRoute] {
        path.filter { if case .crew = $0 { false } else { true } }
    }

    /// Crews with this crew's space on top. Any other space is replaced, so
    /// there is one space (and one live stream) and Back goes to the list.
    static func opening(_ opened: OpenedCrew, in path: [MoreRoute]) -> [MoreRoute] {
        [.section("crews"), .crew(opened)]
    }
}
