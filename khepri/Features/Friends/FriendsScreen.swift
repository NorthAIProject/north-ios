import NorthAPI
import NorthKit
import SwiftUI

/// Friends: your invite link, your handle, who follows you and who you
/// follow. Nobody follows you without your yes, and a follow alone shows them
/// nothing you logged.
struct FriendsScreen: View {
    var service: FriendsServicing = FriendsService()

    @State private var overview: SocialOverview?
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

    private func load() async {
        do {
            let fresh = try await service.overview()
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

private struct PersonRow: View {
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
