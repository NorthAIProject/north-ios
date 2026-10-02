import NorthAPI
import NorthKit
import SwiftUI

/// Friends: your invite link, your handle, who follows you and who you
/// follow. Nobody follows you without your yes, and a follow alone shows them
/// nothing you logged.
struct FriendsScreen: View {
    var service: FriendsServicing = FriendsService()

    @State private var overview: SocialOverview?
    @State private var feed: [FeedItem] = []
    @State private var sharing: Sharing?
    @State private var phone: PhoneStatus?
    @State private var facebook: FacebookFriends?
    @State private var error: String?
    @State private var handle = ""
    @State private var handleError: String?
    @State private var followHandle = ""
    @State private var followError: String?
    @State private var joinedNow = false
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if let overview {
                content(overview)
            } else if let error {
                ContentUnavailableView("Friends did not load", systemImage: "wifi.exclamationmark", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Friends")
        // An invite tapped before this screen could act on it, or while it
        // was already showing.
        .task(id: router.invitesReceived) {
            if await PendingInvite.redeemIfAny(using: service) { joinedNow = true }
            await load()
        }
        .refreshable { await load() }
    }

    private func content(_ o: SocialOverview) -> some View {
        List {
            if let error { ErrorRow(error) }
            if joinedNow {
                Section {
                    Label("You're connected with the friend who invited you.", systemImage: "person.2.fill")
                        .foregroundStyle(NorthColor.signal)
                }
            }

            Section {
                NavigationLink {
                    LeaderboardScreen(inviteURL: URL(string: o.invite.url), friends: service)
                } label: {
                    Label("Leaderboard", systemImage: "trophy")
                }
            }

            Section {
                if feed.isEmpty {
                    Text("Nothing yet. Finish a workout, keep a streak or complete a goal, and it shows here.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(feed, id: \.id) { item in
                    FeedRow(item: item) { act { item.kudoed ? try await service.takeKudos(item.id) : try await service.giveKudos(item.id) } }
                }
            } header: {
                Text("Recent")
            }

            Section {
                if let url = URL(string: o.invite.url) {
                    ShareLink(item: url, message: Text("Join me on Khepri")) {
                        Label("Share Your Invite Link", systemImage: "square.and.arrow.up")
                    }
                }
                Text(o.invite.url).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            } header: {
                Text("Invite")
            } footer: {
                Text(o.joined == 0
                     ? "Anyone who joins through it follows you, and you follow them."
                     : "\(o.joined) \(o.joined == 1 ? "person" : "people") joined through your links.")
            }

            Section {
                HStack {
                    Text("@").foregroundStyle(.secondary)
                    TextField("handle", text: $handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { Task { await saveHandle() } }
                    if handle != o.handle {
                        Button("Save") { Task { await saveHandle() } }
                    }
                }
                if let handleError { ErrorRow(handleError) }
                // Hidden while texting codes is off, unless there is a number to remove.
                if let phone, phone.configured || !phone.number.isEmpty {
                    NavigationLink {
                        PhoneNumberScreen(service: service, status: $phone)
                    } label: {
                        LabeledContent {
                            Text(phone.number.isEmpty ? (phone.pending.isEmpty ? "Add" : "Waiting for code") : phone.number)
                        } label: {
                            Label("Your Phone Number", systemImage: "phone")
                        }
                    }
                }
            } header: {
                Text("Your Handle")
            } footer: {
                Text("How friends find you. Without one, only your invite link does.")
            }

            if !o.requests.isEmpty {
                Section("Waiting for Your Yes") {
                    ForEach(o.requests, id: \.value1.id) { request in
                        PersonRow(person: request.value1)
                            .swipeActions {
                                Button("Decline") { act { try await service.removeFollower(request.value1.id) } }
                                Button("Accept") { act { try await service.accept(request.value1.id) } }
                                    .tint(NorthColor.signal)
                            }
                            .contextMenu {
                                Button("Accept", systemImage: "checkmark") { act { try await service.accept(request.value1.id) } }
                                Button("Decline", systemImage: "xmark") { act { try await service.removeFollower(request.value1.id) } }
                            }
                    }
                }
            }

            if let sharing {
                Section {
                    Toggle("Workouts you finish", isOn: share(\.training, in: sharing))
                    Toggle("Check-in streaks", isOn: share(\.streaks, in: sharing))
                    Toggle("Goals and milestones", isOn: share(\.goals, in: sharing))
                    // Only a server that sent xp accepts it back.
                    if sharing.xp != nil {
                        Toggle("Your XP and level, on friends' leaderboards", isOn: share(\.sharesXP, in: sharing))
                    }
                } header: {
                    Text("What Followers See")
                } footer: {
                    Text("Off until you turn it on. Your journal, decisions, food and health numbers are never shared.")
                }
            }

            Section {
                HStack {
                    TextField("@their_handle", text: $followHandle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await follow() } }
                    Button("Ask to Follow") { Task { await follow() } }
                        .disabled(followHandle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let followError { ErrorRow(followError) }
                NavigationLink {
                    FindContactsScreen(inviteURL: URL(string: o.invite.url), service: service)
                } label: {
                    Label("Find Friends from Contacts", systemImage: "person.crop.circle.badge.plus")
                }
                if let facebook, facebook.configured || facebook.connected {
                    NavigationLink {
                        FacebookFriendsScreen(inviteURL: URL(string: o.invite.url), service: service, facebook: $facebook)
                    } label: {
                        LabeledContent {
                            Text(facebook.connected ? "Connected" : "")
                        } label: {
                            Label("Facebook Friends", systemImage: "person.2.circle")
                        }
                    }
                }
            } header: {
                Text("Follow Somebody")
            }

            Section("Following") {
                if o.following.isEmpty {
                    Text("Nobody yet.").foregroundStyle(.secondary)
                }
                ForEach(o.following, id: \.value1.id) { c in
                    PersonRow(person: c.value1, pending: c.value2.status == .pending)
                        .swipeActions {
                            Button(c.value2.status == .pending ? "Withdraw" : "Unfollow", role: .destructive) {
                                act { try await service.unfollow(c.value1.id) }
                            }
                            Button("Block") { act { try await service.block(c.value1.id) } }
                        }
                }
            }

            Section("Followers") {
                if o.followers.isEmpty {
                    Text("Nobody follows you yet.").foregroundStyle(.secondary)
                }
                ForEach(o.followers, id: \.value1.id) { c in
                    PersonRow(person: c.value1)
                        .swipeActions {
                            Button("Remove", role: .destructive) { act { try await service.removeFollower(c.value1.id) } }
                            Button("Block") { act { try await service.block(c.value1.id) } }
                        }
                }
            }

            if !o.blocked.isEmpty {
                Section("Blocked") {
                    ForEach(o.blocked, id: \.id) { p in
                        PersonRow(person: p)
                            .swipeActions {
                                Button("Unblock") { act { try await service.unblock(p.id) } }
                            }
                    }
                }
            }
        }
    }

    /// A sharing switch that saves as it flips, like Units in Settings.
    private func share(_ keyPath: WritableKeyPath<Sharing, Bool>, in current: Sharing) -> Binding<Bool> {
        Binding(get: { sharing?[keyPath: keyPath] ?? current[keyPath: keyPath] }, set: { on in
            var next = sharing ?? current
            next[keyPath: keyPath] = on
            sharing = next
            Task {
                do { sharing = try await service.setSharing(next) } catch { self.error = error.localizedDescription }
            }
        })
    }

    private func load() async {
        do {
            async let feedNow = service.feed()
            async let sharingNow = service.sharing()
            async let phoneNow = service.phone()
            async let facebookNow = service.facebook()
            let fresh = try await service.overview()
            feed = (try? await feedNow) ?? feed
            sharing = (try? await sharingNow) ?? sharing
            // A server without them answers 404, and the rows stay hidden.
            phone = (try? await phoneNow) ?? phone
            facebook = (try? await facebookNow) ?? facebook
            overview = fresh
            if handle.isEmpty || handle == overview?.handle { handle = fresh.handle }
            error = nil
        } catch {
            if overview == nil { self.error = error.localizedDescription }
        }
    }

    private func saveHandle() async {
        do {
            handle = try await service.setHandle(handle)
            handleError = nil
            await load()
        } catch {
            handleError = error.localizedDescription
        }
    }

    private func follow() async {
        do {
            try await service.follow(handle: followHandle)
            followHandle = ""
            followError = nil
            await load()
        } catch {
            followError = error.localizedDescription
        }
    }

    private func act(_ action: @escaping () async throws -> Void) {
        Task {
            do { try await action(); error = nil } catch { self.error = error.localizedDescription }
            await load()
        }
    }
}

struct PersonRow: View {
    let person: PublicPerson
    var pending = false

    var body: some View {
        HStack(spacing: 12) {
            Text(initials)
                .font(.subheadline.weight(.medium))
                .frame(width: 36, height: 36)
                .background(Color(.secondarySystemFill), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName)
                Text(person.handle.isEmpty ? "No handle" : "@\(person.handle)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if pending {
                Text("Waiting").northEyebrow()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var initials: String {
        let letters = person.displayName.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

/// One moment: who, what, when, and kudos.
private struct FeedRow: View {
    let item: FeedItem
    let toggleKudos: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.mine ? "You" : item.displayName).font(.subheadline.weight(.medium))
                    Text("· \(item.occurredAt.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(item.title)
                if !item.detail.isEmpty {
                    Text(item.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if item.mine {
                if item.kudos > 0 {
                    Label("\(item.kudos)", systemImage: "hands.clap.fill")
                        .font(.caption.monospacedDigit()).foregroundStyle(NorthColor.signal)
                        .accessibilityLabel("\(item.kudos) kudos")
                }
            } else {
                Button(action: toggleKudos) {
                    Label(item.kudos > 0 ? "\(item.kudos)" : "Kudos", systemImage: item.kudoed ? "hands.clap.fill" : "hands.clap")
                        .font(.caption.monospacedDigit())
                }
                .buttonStyle(.bordered)
                .tint(item.kudoed ? NorthColor.signal : .secondary)
                .accessibilityLabel(item.kudoed ? "Take back kudos" : "Give kudos")
                .sensoryFeedback(.success, trigger: item.kudoed) { _, given in given }
            }
        }
        .padding(.vertical, 2)
    }
}
