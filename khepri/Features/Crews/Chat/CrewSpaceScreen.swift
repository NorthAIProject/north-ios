import NorthAPI
import NorthKit
import SwiftUI

/// A crew's own space: its chat, one channel at a time, and the week's
/// challenge. While it is in front it holds the crew's live stream and hands
/// each event to the open channel.
struct CrewSpaceScreen: View {
    let crew: Crew
    let meID: String
    let crews: CrewsServicing
    var chat: CrewChatServicing = CrewChatService()
    /// The channel a push or link opened this space on; nil (or a channel
    /// that is gone) is the crew's default one.
    var firstChannelID: String?

    enum Tab: Hashable { case chat, challenge }

    @State private var tab: Tab = .chat
    @State private var space: CrewSpace?
    @State private var store: CrewChatStore?
    @State private var error: String?
    @State private var showingPins = false
    @State private var showingNotify = false
    /// Why the crew closed for this person: shown once, then back to the list.
    @State private var closed: String?
    @State private var showingClosed = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(CrewUnread.self) private var crewUnread
    /// Its `crewChannelRequest` is a push or link for the crew already open:
    /// each new one moves this space to its channel, and to Chat.
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            switch tab {
            case .chat: chatTab
            case .challenge: CrewBoardView(crewID: crew.id, service: crews, chat: chat)
            }
        }
        .navigationTitle(crew.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Crews", selection: $tab) {
                    Text("Chat").tag(Tab.chat)
                    Text("Challenge").tag(Tab.challenge)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            if tab == .chat, let store {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    channelMenu(openID: store.channelID)
                    Button("Pinned messages", systemImage: "pin") { showingPins = true }
                    Button("Notifications", systemImage: notifyIcon) { showingNotify = true }
                }
            }
        }
        .task { await loadSpace() }
        .onChange(of: router.crewChannelRequest) {
            Task { await follow(router.crewChannelRequest) }
        }
        // What was read here, and what came in elsewhere, is the server's to
        // count: the crew badges ask it again on the way out.
        .onDisappear { Task { await crewUnread.refresh() } }
        // The stream runs only while the app is in front; nothing is replayed,
        // so every (re)connect makes the channel resync.
        .task(id: scenePhase) {
            guard scenePhase == .active, closed == nil else { return }
            for await event in CrewLiveStream(crewID: crew.id, service: chat).events() {
                let closing = await route(event)
                if closing { break }
            }
        }
        .onChange(of: store?.closedReason) {
            if let reason = store?.closedReason { close(reason) }
        }
        .alert(closed ?? "", isPresented: $showingClosed) {
            Button("OK") { dismiss() }
        }
        .sheet(isPresented: $showingPins) {
            if let store {
                CrewPinsSheet(crewID: crew.id, channelID: store.channelID, service: chat)
            }
        }
        .sheet(isPresented: $showingNotify) {
            CrewNotifySheet(current: space?.notify) { notify, mutedUntil in
                Task { await saveNotify(notify, mutedUntil: mutedUntil) }
            }
        }
    }

    @ViewBuilder private var chatTab: some View {
        if let store {
            ChannelView(store: store, channelName: channelName(store.channelID), role: CrewRole(space?.myRole))
                .id(store.channelID)
                .overlay(alignment: .top) {
                    if let error {
                        CrewErrorBanner(text: error) { self.error = nil }
                    }
                }
        } else if let error {
            ContentUnavailableView(crew.name, systemImage: "wifi.exclamationmark", description: Text(error))
        } else {
            ProgressView()
        }
    }

    // MARK: Channels

    /// Text channels only: a kind this build does not know stays hidden.
    private var channels: [CrewChannel] {
        (space?.channels ?? []).filter { $0.kind == "text" }
    }

    private func channelName(_ id: String) -> String {
        channels.first { $0.id == id }?.name ?? ""
    }

    private var notifyIcon: String {
        if let until = space?.mutedUntil, until > Date() { return "bell.slash" }
        return space?.notify == "none" ? "bell.slash" : "bell"
    }

    private func channelMenu(openID: String) -> some View {
        Menu {
            Picker("Channels", selection: Binding(get: { openID }, set: { id in
                if let channel = channels.first(where: { $0.id == id }) { open(channel) }
            })) {
                ForEach(channels, id: \.id) { channel in
                    Text(verbatim: menuTitle(channel, isOpen: channel.id == openID)).tag(channel.id)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(verbatim: "#\(channelName(openID))")
                .lineLimit(1)
                .frame(maxWidth: 110)
        }
        .accessibilityLabel(Text("Channels"))
        .accessibilityValue(Text(verbatim: "#\(channelName(openID))"))
    }

    /// "#name", then the unread count, with an @ when some mention you.
    private func menuTitle(_ channel: CrewChannel, isOpen: Bool) -> String {
        let name = "#\(channel.name ?? "")"
        let unread = isOpen ? 0 : channel.unread ?? 0
        guard unread > 0 else { return name }
        let mention = (channel.mentions ?? 0) > 0 ? "@ " : ""
        return "\(name)  ·  \(mention)\(unread)"
    }

    private func open(_ channel: CrewChannel) {
        guard channel.id != store?.channelID else { return }
        store = CrewChatStore(crewID: crew.id, channelID: channel.id, meID: meID, service: chat)
        clearUnread(channel.id)
    }

    /// A push or link for this crew while it is open: back to the chat, on
    /// the linked channel. A channel this build has not seen yet makes the
    /// space reload first.
    private func follow(_ request: CrewRoute?) async {
        guard let request, request.crewID == crew.id.lowercased() else { return }
        tab = .chat
        guard let wanted = request.channelID else { return }
        if !channels.contains(where: { $0.id.lowercased() == wanted }) { await loadSpace() }
        if let channel = channels.first(where: { $0.id.lowercased() == wanted }) { open(channel) }
    }

    // MARK: Loading and live events

    /// Loads the space and keeps the open channel, or opens the default one
    /// when there is none or it is gone.
    private func loadSpace() async {
        do {
            space = try await chat.space(crew.id)
            error = nil
        } catch {
            self.error = error.localizedDescription
            return
        }
        if let open = store?.channelID, channels.contains(where: { $0.id == open }) {
            clearUnread(open)
            return
        }
        // The first load may start on a pushed channel; later ones fall back
        // to the default.
        let wanted = store == nil ? firstChannelID?.lowercased() : nil
        let linked = channels.first { $0.id.lowercased() == wanted }
        if let first = linked ?? channels.first(where: { $0._default == true }) ?? channels.first {
            store = nil
            open(first)
        }
    }

    /// Hands an event on. True when the crew is closed for this person: stop listening.
    private func route(_ event: CrewLiveEvent) async -> Bool {
        switch event {
        case .removed(let userID) where userID.isEmpty || userID == meID:
            await store?.handle(event)
            close(store?.closedReason ?? String(localized: "You're no longer in this crew"))
            return true
        case .channels:
            await loadSpace()
        case .connected, .resync:
            await loadSpace()
            await store?.handle(event)
        case .message(let channelID, _) where channelID != store?.channelID:
            bumpUnread(channelID)
        default:
            await store?.handle(event)
        }
        return false
    }

    private func close(_ reason: String) {
        guard closed == nil else { return }
        closed = reason
        showingClosed = true
        // Out of the crew: its messages stop counting.
        crewUnread.clear(crewID: crew.id)
    }

    private func bumpUnread(_ channelID: String) {
        guard let index = space?.channels?.firstIndex(where: { $0.id == channelID }) else { return }
        space?.channels?[index].unread = (space?.channels?[index].unread ?? 0) + 1
    }

    private func clearUnread(_ channelID: String) {
        guard let index = space?.channels?.firstIndex(where: { $0.id == channelID }) else { return }
        space?.channels?[index].unread = 0
        space?.channels?[index].mentions = 0
    }

    private func saveNotify(_ notify: String, mutedUntil: Date?) async {
        do {
            try await chat.setNotify(crew.id, notify: notify, mutedUntil: mutedUntil)
            await loadSpace()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
