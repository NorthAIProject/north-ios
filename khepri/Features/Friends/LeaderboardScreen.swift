import NorthAPI
import NorthKit
import SwiftUI

/// Your level and XP, and you ranked against the friends who share with you.
/// XP comes only from things done: workouts, habits kept, streaks, milestones
/// and goals.
struct LeaderboardScreen: View {
    /// Your invite link, offered while nobody else is on the board.
    var inviteURL: URL?
    var service: LeaderboardServicing = LeaderboardService()
    /// Where the sharing switches live; turning one on puts you on a board.
    var friends: FriendsServicing = FriendsService()

    @State private var selected: LeaderboardBoard = .xpWeek
    @State private var summary: XPSummary?
    @State private var board: Leaderboard?
    @State private var error: String?
    @State private var turningOn = false

    var body: some View {
        Group {
            if let summary {
                content(summary)
            } else if let error {
                ContentUnavailableView("The leaderboard did not load", systemImage: "wifi.exclamationmark", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Leaderboard")
        // The first run loads the level card too; a new pick only its board.
        .task(id: selected) { summary == nil ? await load() : await loadBoard() }
        .refreshable { await load() }
    }

    private func content(_ summary: XPSummary) -> some View {
        List {
            if let error { ErrorRow(error) }

            Section {
                LevelCard(total: summary.total, level: summary.level)
            } footer: {
                Text("XP comes only from things done: workouts, habits kept, streaks, milestones and goals.")
            }

            Section {
                ForEach(summary.week, id: \.kind) { earned in
                    LabeledContent(XPFormat.kindLabel(earned.kind)) {
                        Text(XPFormat.earned(count: earned.count, points: earned.points)).monospacedDigit()
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("\(summary.weekTotal) XP This Week")
            }

            Section {
                Picker("Board", selection: $selected) {
                    ForEach(LeaderboardBoard.allCases) { board in
                        Text(board.segment).tag(board)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            boardSection
        }
    }

    @ViewBuilder
    private var boardSection: some View {
        if let board {
            Section {
                ForEach(board.entries, id: \.userId) { entry in
                    LeaderboardRow(entry: entry, value: XPFormat.value(entry.value, metric: board.metric))
                }
                if board.entries.count <= 1 {
                    Text("Only you so far. Friends appear here once they share this with followers.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let inviteURL {
                        ShareLink(item: inviteURL, message: Text("Join me on Khepri")) {
                            Label("Share Your Invite Link", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            } header: {
                Text(selected.label)
            }

            if !board.sharing {
                Section {
                    Text("Your friends don't see you on this board.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button(selected.shareAction) { Task { await turnOnSharing() } }
                        .disabled(turningOn)
                } footer: {
                    Text("You can change it any time under What Followers See on Friends.")
                }
            }
        } else {
            Section {
                ProgressView().frame(maxWidth: .infinity)
            } header: {
                Text(selected.label)
            }
        }
    }

    private func load() async {
        do {
            async let boardNow = service.board(selected)
            summary = try await service.summary()
            board = try await boardNow
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadBoard() async {
        let wanted = selected
        do {
            let fresh = try await service.board(wanted)
            // A slower answer for a board no longer picked would mislabel it.
            if wanted == selected { board = fresh; error = nil }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Turns on the switch this board needs, then shows the board again.
    private func turnOnSharing() async {
        turningOn = true
        defer { turningOn = false }
        do {
            let current = try await friends.sharing()
            _ = try await friends.setSharing(current.turningOn(selected))
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Level number and title, progress to the next one, and lifetime XP.
private struct LevelCard: View {
    let total: Int
    let level: XPLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Level \(level.number)").northEyebrow()
            Text(level.title).font(.title2.weight(.semibold))
            if let progress = XPFormat.progress(total: total, floor: level.floor, next: level.next) {
                ProgressView(value: progress)
                    .tint(NorthColor.signal)
                    .accessibilityLabel("Progress to the next level")
            }
            Text(XPFormat.levelCaption(total: total, next: level.next))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// One place on the board: rank, who, their level on XP boards, and value.
private struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                .frame(minWidth: 20, alignment: .trailing)
            Text(initial)
                .font(.subheadline.weight(.medium))
                .frame(width: 36, height: 36)
                .background(Color(.secondarySystemFill), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.displayName).fontWeight(entry.me ? .semibold : .regular)
                    if entry.me { Text("(you)").foregroundStyle(.secondary) }
                }
                .lineLimit(1)
                if !entry.handle.isEmpty {
                    Text("@\(entry.handle)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let level = entry.level {
                Text(level.title)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(.secondary.opacity(0.4)))
            }
            Text(value).font(.subheadline.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    private var initial: String {
        entry.displayName.first.map { String($0).uppercased() } ?? "?"
    }
}
