import NorthAPI
import NorthKit
import SwiftUI

/// One person: who they are, what they share, and a button to follow them.
/// Sections follow the owner's sharing switches; the server leaves out what
/// you may not see, and this screen says "isn't shared" rather than nothing.
struct ProfileScreen: View {
    let handle: String
    var service: ProfileServicing = ProfileService()
    var friends: FriendsServicing = FriendsService()

    @State private var profile: ProfileView?
    @State private var error: String?
    @State private var actionError: String?
    @State private var isWorking = false
    @State private var shownAward: Award?

    var body: some View {
        Group {
            if let profile {
                content(ProfileModel(profile), userID: profile.value1.id)
            } else if let error {
                ContentUnavailableView {
                    Label("Profile did not load", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("@\(handle)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $shownAward) { award in
            AwardDetailSheet(award: award)
                .presentationDetents([.medium, .large])
        }
    }

    private func content(_ model: ProfileModel, userID: String) -> some View {
        List {
            Section { header(model, userID: userID) }
            if let actionError { Section { ErrorRow(actionError) } }
            Section {
                switch model.awards {
                case .hidden:
                    Text("Awards aren't shared.").foregroundStyle(.secondary)
                case .empty:
                    Text("No awards yet.").foregroundStyle(.secondary)
                    if model.awardsLink == .mine { NavigationLink("See All") { AwardsScreen() } }
                case .list(let held):
                    awardsStrip(held)
                    switch model.awardsLink {
                    case .mine:
                        NavigationLink("See All") { AwardsScreen() }
                    case .theirs:
                        NavigationLink("See All") { ProfileAwardsScreen(name: model.name, awards: held) }
                    case nil:
                        EmptyView()
                    }
                }
            } header: {
                Text("Awards")
            }
            Section {
                switch model.workouts {
                case .hidden:
                    Text("Workouts aren't shared.").foregroundStyle(.secondary)
                case .empty:
                    Text("No workouts yet.").foregroundStyle(.secondary)
                case .list(let cards):
                    ForEach(cards, id: \.sessionId) { card in
                        NavigationLink {
                            WorkoutDetailScreen(handle: handle, card: card, authorName: model.name)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.titleLine).font(.subheadline)
                                WorkoutCardView(card: card)
                            }
                        }
                    }
                    NavigationLink("See All") {
                        ProfileWorkoutsScreen(handle: handle, name: model.name, service: service)
                    }
                }
            } header: {
                Text("Workouts")
            }
        }
    }

    private func awardsStrip(_ held: [Award]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(held, id: \.id) { award in
                    Button { shownAward = award } label: {
                        AwardCoin(award: award, size: 52)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(award.name)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func header(_ model: ProfileModel, userID: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(PersonRow.initials(of: model.name))
                    .font(.title3.weight(.medium))
                    .frame(width: 56, height: 56)
                    .background(Color(.secondarySystemFill), in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name).font(.title2.weight(.medium))
                    Text("@\(model.handle)").font(.subheadline).foregroundStyle(.secondary)
                    if let level = model.level {
                        Text("Level \(level.number) · \(level.title)").font(.subheadline)
                    }
                }
            }
            HStack(spacing: 16) {
                if let count = model.workoutCount { stat(count, "Workouts") }
                stat(model.followers, "Followers")
                stat(model.following, "Following")
            }
            .font(.subheadline)
            if model.canFollow {
                Button {
                    Task { await toggleFollow(model, userID: userID) }
                } label: {
                    Text(model.isFollowing ? "Unfollow" : "Follow").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isFollowing ? .secondary : NorthColor.signal)
                .disabled(isWorking)
            }
        }
        .padding(.vertical, 4)
    }

    private func stat(_ value: Int, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Text(value.formatted()).monospacedDigit()
            Text(label).foregroundStyle(.secondary)
        }
    }

    private func load() async {
        do {
            profile = try await service.profile(handle: handle)
            error = nil
            actionError = nil
        } catch {
            // Keep what is showing and say the refresh failed.
            if profile == nil { self.error = error.localizedDescription } else { actionError = error.localizedDescription }
        }
    }

    private func toggleFollow(_ model: ProfileModel, userID: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            if model.isFollowing {
                try await friends.unfollow(userID)
            } else {
                try await friends.follow(handle: handle)
            }
            actionError = nil
            await load()
        } catch {
            actionError = error.localizedDescription
        }
    }
}
