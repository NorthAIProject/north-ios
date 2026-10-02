import AuthenticationServices
import NorthAPI
import NorthKit
import SwiftUI

/// What the server's Facebook callback says happened, read from
/// khepri://friends/facebook?result=…
enum FacebookConnectResult: Equatable {
    case connected, cancelled, expired, taken, failed

    init(callback: URL) {
        let result = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "result" }?.value
        switch result {
        case "connected": self = .connected
        case "cancelled": self = .cancelled
        case "expired": self = .expired
        case "taken": self = .taken
        default: self = .failed
        }
    }

    var message: String? {
        switch self {
        case .connected: nil
        case .cancelled: "Facebook was not connected."
        case .expired: "That took too long. Try connecting again."
        case .taken: "This Facebook account is already connected to another Khepri account."
        case .failed: "Facebook did not connect. Try again in a moment."
        }
    }
}

/// Facebook friends: connect through Facebook's own sign-in, the same way as
/// Strava, and see which of your Facebook friends are on Khepri. The server
/// keeps no Facebook token, so finding them again means connecting again.
struct FacebookFriendsScreen: View {
    /// Your invite link, offered when nobody was found.
    let inviteURL: URL?
    var service: FriendsServicing = FriendsService()
    /// Shared with Friends, so its row is current on the way back.
    @Binding var facebook: FacebookFriends?

    @State private var error: String?
    @State private var working = false
    @State private var confirmingDisconnect = false
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        List {
            if let error { ErrorRow(error) }
            if let facebook {
                if facebook.connected {
                    connected(facebook)
                } else {
                    Section {
                        Button("Connect Facebook") { Task { await connect() } }
                            .disabled(working || !facebook.configured)
                    } footer: {
                        Text("Opens Facebook to sign in. Friends who also connected Facebook to Khepri show here. Nothing is posted to Facebook.")
                    }
                }
            } else if error == nil {
                ProgressView()
            }
        }
        .navigationTitle("Facebook Friends")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog("Disconnect Facebook?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await run { try await service.disconnectFacebook() } } }
        } message: {
            Text("People you follow stay followed.")
        }
    }

    @ViewBuilder
    private func connected(_ facebook: FacebookFriends) -> some View {
        let people = facebook.people.map { ContactMatch(person: $0.value1, following: $0.value2.following) }
        if people.isEmpty {
            Section {
                Text(facebook.importedAt == nil
                     ? "Tap Find Again to see which of your Facebook friends are on Khepri."
                     : "None of your Facebook friends have connected Khepri yet.")
                    .foregroundStyle(.secondary)
                if let inviteURL {
                    ShareLink(item: inviteURL, message: Text("Join me on Khepri")) {
                        Label("Share Your Invite Link", systemImage: "square.and.arrow.up")
                    }
                }
            }
        } else {
            Section {
                ForEach(people) { match in
                    MatchRow(match: match) { follow(match) }
                }
            } header: {
                Text("On Khepri")
            } footer: {
                if let at = facebook.importedAt {
                    Text("Found \(at.formatted(.relative(presentation: .named))).")
                }
            }
        }
        Section {
            Button("Find Again") { Task { await connect() } }
                .disabled(working || !facebook.configured)
            Button("Disconnect Facebook", role: .destructive) { confirmingDisconnect = true }
                .disabled(working)
        }
    }

    private func load() async {
        do { facebook = try await service.facebook(); error = nil } catch { self.error = error.localizedDescription }
    }

    private func run(_ action: () async throws -> Void) async {
        working = true
        defer { working = false }
        do { try await action(); error = nil; await load() } catch { self.error = error.localizedDescription }
    }

    /// Facebook's sign-in in a shared browser session, so somebody already
    /// signed in to Facebook in Safari only has to agree.
    private func connect() async {
        working = true
        defer { working = false }
        do {
            let url = try await service.facebookAuthorizeURL()
            let callback = try await webAuthenticationSession.authenticate(
                using: url, callbackURLScheme: "khepri", preferredBrowserSession: .shared)
            let outcome = FacebookConnectResult(callback: callback).message
            await load()
            if let outcome { error = outcome }
        } catch let authError as ASWebAuthenticationSessionError where authError.code == .canceledLogin {
            // Closing the sheet is an answer, not an error.
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func follow(_ match: ContactMatch) {
        Task {
            do {
                let connection = try await service.follow(handle: match.person.handle)
                guard let i = facebook?.people.firstIndex(where: { $0.value1.id == match.id }) else { return }
                facebook?.people[i].value2.following = connection.value2.status.rawValue
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
