import NorthAPI
import NorthKit
import SwiftUI

/// Find friends from contacts: who among your contacts is already on Khepri.
/// Their email addresses and phone numbers are hashed on the phone and only
/// the hashes are sent; nothing about your contacts is kept, here or on the
/// server.
struct FindContactsScreen: View {
    /// Your invite link, offered when nobody matched.
    let inviteURL: URL?
    var service: FriendsServicing = FriendsService()

    @State private var phase = Phase.starting
    @State private var limited = false
    @State private var error: String?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    enum Phase: Equatable {
        case starting, asking, refused, restricted, checking
        case found([ContactMatch])
        case failed(String)
    }

    var body: some View {
        Group {
            switch phase {
            case .starting, .checking:
                ProgressView("Checking your contacts")
            case .asking:
                asking
            case .refused:
                refused
            case .restricted:
                ContentUnavailableView("Contacts Are Restricted", systemImage: "person.crop.circle.badge.xmark",
                                       description: Text("This iPhone doesn't allow Khepri to read contacts."))
            case .found(let people) where people.isEmpty:
                nobody
            case .found(let people):
                found(people)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Contacts Were Not Checked", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await check() } }
                }
            }
        }
        .navigationTitle("From Contacts")
        .navigationBarTitleDisplayMode(.inline)
        .task { await begin() }
        // Back from Settings with Contacts allowed.
        .onChange(of: scenePhase) { _, now in
            if now == .active, phase == .refused { Task { await begin() } }
        }
    }

    private var asking: some View {
        ContentUnavailableView {
            Label("Find Friends from Contacts", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("Only hashed copies of your contacts' email addresses and phone numbers leave this iPhone, and nothing is kept.")
        } actions: {
            Button("Continue") {
                Task {
                    _ = await ContactBook.requestAccess()
                    await begin()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var refused: some View {
        ContentUnavailableView {
            Label("Contacts Are Off", systemImage: "person.crop.circle.badge.xmark")
        } description: {
            Text("Allow Contacts for Khepri in Settings to see who is already here.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
    }

    private var nobody: some View {
        ContentUnavailableView {
            Label("None of your contacts are on Khepri yet", systemImage: "person.2")
        } description: {
            Text(limited ? "Only the contacts you chose for Khepri were checked." : "Send them your invite link.")
        } actions: {
            if let inviteURL {
                ShareLink(item: inviteURL, message: Text("Join me on Khepri")) {
                    Label("Share Your Invite Link", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func found(_ people: [ContactMatch]) -> some View {
        List {
            if let error { ErrorRow(error) }
            Section {
                ForEach(people) { match in
                    MatchRow(match: match) { follow(match) }
                }
            } header: {
                Text("On Khepri")
            } footer: {
                Text(limited
                     ? "Only the contacts you chose for Khepri were checked, by hashed email and phone number."
                     : "Only hashed email addresses and phone numbers left this iPhone, and nothing was kept.")
            }
        }
        .refreshable { await check() }
    }

    private func begin() async {
        switch ContactBook.access {
        case .undecided: phase = .asking
        case .refused: phase = .refused
        case .restricted: phase = .restricted
        case .allowed, .limited: await check()
        }
    }

    private func check() async {
        limited = ContactBook.access == .limited
        if case .found = phase {} else { phase = .checking }
        do {
            let hashes = try await ContactBook.hashes(home: await homeCallingCode())
            phase = .found(try await ContactMatching.matchAll(hashes) { try await service.matchContacts($0) })
            error = nil
        } catch is CancellationError {
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// The country numbers saved without "+" are read in: your verified
    /// number's, else this iPhone's region. Nil skips those numbers.
    private func homeCallingCode() async -> CallingCode? {
        if let number = try? await service.phone().number, let code = PhoneNumbers.callingCode(of: number) {
            return code
        }
        return PhoneNumbers.callingCode(region: Locale.current.region?.identifier)
    }

    private func follow(_ match: ContactMatch) {
        Task {
            do {
                let connection = try await service.follow(handle: match.person.handle)
                guard case .found(var people) = phase, let i = people.firstIndex(where: { $0.id == match.id }) else { return }
                people[i].following = connection.value2.status.rawValue
                phase = .found(people)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// A person found in your contacts or on Facebook, with the same
/// ask-to-follow as Friends.
struct MatchRow: View {
    let match: ContactMatch
    let follow: () -> Void

    var body: some View {
        HStack {
            PersonRow(person: match.person, pending: match.following == "pending")
            switch match.following {
            case "":
                Button("Ask to Follow", action: follow)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            case "accepted":
                Text("Following").northEyebrow()
            default:
                EmptyView()
            }
        }
        .sensoryFeedback(.success, trigger: match.following) { _, now in now == "pending" || now == "accepted" }
    }
}
