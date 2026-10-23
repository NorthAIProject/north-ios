import NorthAPI
import os
import SwiftUI

/// Everything that does not earn a tab: the rest of the web app's sections,
/// and Settings.
struct MoreScreen: View {
    let user: APIUser
    @Environment(AppRouter.self) private var router
    @Environment(CrewUnread.self) private var crewUnread
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [MoreRoute] = []
    /// A crew push or link waiting for the app to be in front: a push the
    /// stack gets while it is not can be missed.
    @State private var pendingCrew: CrewRoute?
    /// The crew route being followed. A newer one cancels it.
    @State private var following: Task<Void, Never>?
    /// The crew space opening on screen, as it reports itself. The path alone
    /// can name a space the stack never showed.
    @State private var shownCrew: UUID?
    private let crewsService: CrewsServicing = CrewsService()
    private static let log = Logger(subsystem: "com.fernandocorreia.khepri", category: "crews")

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
        .init(id: "awards", title: "Awards", systemImage: "rosette"),
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
                    .onAppear { shownCrew = opened.id }
                    .onDisappear { if shownCrew == opened.id { shownCrew = nil } }
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
            pendingCrew = route
            followPending()
        }
        .onChange(of: scenePhase) { followPending() }
        // A crew's join link, opened while signed in or kept from before.
        // Joined here too, not by the Crews list an open space may cover.
        .task(id: router.crewLinksReceived) {
            guard let joined = await PendingCrewJoin.joinIfAny(using: crewsService) else { return }
            pendingCrew = CrewRoute(crewID: joined.id.lowercased(), channelID: nil)
            followPending()
        }
        // A widget, a shortcut or a nudge naming a section lands on it.
        .onChange(of: router.openSection, initial: true) { _, id in
            guard let id else { return }
            router.openSection = nil
            let next = MorePath.opening(section: id, in: path)
            if next != path { path = next }
        }
    }

    /// Follows the waiting crew route once the app is in front, one at a time.
    private func followPending() {
        guard scenePhase == .active, let route = pendingCrew else { return }
        pendingCrew = nil
        following?.cancel()
        following = Task { await follow(route) }
    }

    /// The open crew moves to the linked channel; any other crew's space
    /// replaces it. A crew you are not in (any more) leaves the list showing.
    private func follow(_ route: CrewRoute) async {
        switch CrewLinkLanding(route, openCrewID: MorePath.shownCrewID(in: path, shown: shownCrew)) {
        case .switchChannel:
            router.crewChannelRequest = route
        case .openSpace:
            let crews: [Crew]
            do {
                crews = try await crewsService.crews()
            } catch {
                // The list shows the error and a way to retry.
                Self.log.error("crew link: loading crews failed: \(error.localizedDescription, privacy: .private)")
                path = MorePath.opening(section: "crews", in: MorePath.closingCrew(in: path))
                return
            }
            guard !Task.isCancelled else { return }
            guard let crew = crews.first(where: { $0.id.lowercased() == route.crewID }) else {
                Self.log.notice("crew link: not a member of the linked crew")
                return
            }
            await push(OpenedCrew(crew: crew, channelID: route.channelID))
        }
    }

    /// Pushes a crew's space over Crews, closing any other first, until the
    /// space reports itself on screen.
    private func push(_ opened: OpenedCrew) async {
        for attempt in 1...3 {
            if MorePath.closingCrew(in: path) != path {
                // Swapping the top of the stack in place is not reliable: the
                // stack often kept showing the old space. Close it without
                // animation, then push the new one.
                var closing = Transaction()
                closing.disablesAnimations = true
                withTransaction(closing) { path = MorePath.closingCrew(in: path) }
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
            }
            path = MorePath.opening(opened, in: path)
            // Up to a second for the space to appear.
            var waited = 0
            while shownCrew != opened.id, !Task.isCancelled, waited < 20 {
                try? await Task.sleep(for: .milliseconds(50))
                waited += 1
            }
            if shownCrew == opened.id || Task.isCancelled { return }
            Self.log.notice("crew link: space not shown after push \(attempt, privacy: .public); pushing again")
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
        case "awards": AwardsScreen()
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

    /// The crew on top of the stack, lowercased, only if that opening is the
    /// one on screen: a push the stack missed is not open.
    static func shownCrewID(in path: [MoreRoute], shown: UUID?) -> String? {
        guard case .crew(let opened) = path.last, opened.id == shown else { return nil }
        return openCrewID(in: path)
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
