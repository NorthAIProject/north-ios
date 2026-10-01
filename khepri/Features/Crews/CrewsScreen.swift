import NorthAPI
import NorthKit
import SwiftUI

/// Crews: a few people keeping each other going. Crewmates see who checked in
/// and trained today, streaks and the week's challenge, and nothing else.
struct CrewsScreen: View {
    var service: CrewsServicing = CrewsService()

    @State private var crews: [Crew] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var naming = false
    @State private var newName = ""
    @State private var opened: Crew?
    @Environment(AppRouter.self) private var router

    var body: some View {
        List {
            if let error { ErrorRow(error) }
            if loaded, crews.isEmpty {
                Text("A crew is up to eight people who keep each other going. Two is an accountability partner.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            // Destination links, not value links: Crews is itself pushed with
            // one from More, and mixing the two in one stack misplaces screens.
            ForEach(crews, id: \.id) { crew in
                NavigationLink {
                    CrewBoardView(crewID: crew.id, service: service) { Task { await load() } }
                } label: {
                    HStack {
                        Text(crew.name)
                        Spacer()
                        Text("\(crew.memberCount) people").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Crews")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Crew", systemImage: "plus") { naming = true }
            }
        }
        .alert("Name the crew", isPresented: $naming) {
            TextField("e.g. Morning runners", text: $newName)
            Button("Create") { Task { await create() } }
            Button("Cancel", role: .cancel) { newName = "" }
        }
        // A crew just made or joined opens over the list.
        .sheet(item: $opened) { crew in
            NavigationStack {
                CrewBoardView(crewID: crew.id, service: service) { Task { await load() } }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { opened = nil }
                        }
                    }
            }
        }
        // A crew link opened while here, or before signing in.
        .task(id: router.crewLinksReceived) {
            if let joined = await PendingCrewJoin.joinIfAny(using: service) {
                await load()
                opened = joined
            } else {
                await load()
            }
        }
        .refreshable { await load() }
    }

    private func load() async {
        do { crews = try await service.crews(); error = nil } catch { self.error = error.localizedDescription }
        loaded = true
    }

    private func create() async {
        let name = newName
        newName = ""
        do {
            let crew = try await service.create(name: name)
            await load()
            opened = crew
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension Crew: @retroactive Identifiable {}
extension Crew: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One crew: everybody's day, streak and week.
struct CrewBoardView: View {
    let crewID: String
    let service: CrewsServicing
    let onChange: () -> Void

    @State private var board: CrewBoard?
    @State private var error: String?
    @State private var confirmingLeave = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let error { ErrorRow(error) }
            if let board {
                Section {
                    ForEach(board.value2.members, id: \.id) { member in
                        MemberRow(member: member, challenge: board.value2.challenge)
                            .swipeActions {
                                if board.value2.isOwner && !member.me {
                                    Button("Remove", role: .destructive) {
                                        act { try await service.remove(crewID, member: member.id) }
                                    }
                                }
                            }
                    }
                } header: {
                    Text("Today")
                } footer: {
                    Text(challengeText(board.value2.challenge))
                }

                Section {
                    if let url = URL(string: board.value1.joinUrl) {
                        ShareLink(item: url, message: Text("Join \(board.value1.name) on Khepri")) {
                            Label("Invite to the Crew", systemImage: "person.badge.plus")
                        }
                    }
                } footer: {
                    Text("\(board.value2.members.count) of up to 8. Anyone with the link can join.")
                }

                if board.value2.isOwner {
                    ChallengeEditor(current: board.value2.challenge) { challenge in
                        act { try await service.setChallenge(crewID, challenge) }
                    }
                }

                Section {
                    Button("Leave Crew", role: .destructive) { confirmingLeave = true }
                }
            } else if error == nil {
                ProgressView()
            }
        }
        .navigationTitle(board?.value1.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Leave this crew?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                Task {
                    guard let me = board?.value2.members.first(where: \.me) else { return }
                    do {
                        try await service.remove(crewID, member: me.id)
                        onChange()
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { board = try await service.board(crewID); error = nil } catch { self.error = error.localizedDescription }
    }

    private func act(_ action: @escaping () async throws -> Void) {
        Task {
            do { try await action(); error = nil } catch { self.error = error.localizedDescription }
            await load()
            onChange()
        }
    }

    private func challengeText(_ challenge: CrewChallenge?) -> String {
        guard let challenge else { return "No challenge this week." }
        let noun = challenge.kind == .workouts ? "workouts" : "check-ins"
        return "\(challenge.target) \(noun) each, Monday to Sunday."
    }
}

private struct MemberRow: View {
    let member: CrewMember
    let challenge: CrewChallenge?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(member.me ? "You" : member.displayName).font(.subheadline.weight(.medium))
                if member.owner { Text("owner").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Image(systemName: member.checkedIn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(member.checkedIn ? NorthColor.signal : .secondary)
                    .accessibilityLabel(member.checkedIn ? "Checked in" : "Not checked in yet")
                if member.workedOut {
                    Image(systemName: "figure.run").foregroundStyle(NorthColor.signal)
                        .accessibilityLabel("Trained today")
                }
            }
            Text("\(member.streak)-day check-in streak").font(.caption).foregroundStyle(.secondary)
            if let challenge {
                ProgressView(value: Double(min(member.weekProgress, challenge.target)), total: Double(challenge.target)) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(member.weekProgress)/\(challenge.target)").font(.caption2.monospacedDigit())
                }
                .tint(NorthColor.signal)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// The owner's weekly challenge: what, and how many times.
private struct ChallengeEditor: View {
    let current: CrewChallenge?
    let save: (CrewChallenge?) -> Void

    @State private var kind: CrewChallenge.KindPayload?
    @State private var target = 3

    var body: some View {
        Section("Weekly Challenge") {
            Picker("What", selection: $kind) {
                Text("No challenge").tag(CrewChallenge.KindPayload?.none)
                Text("Check-ins").tag(Optional(CrewChallenge.KindPayload.checkins))
                Text("Workouts").tag(Optional(CrewChallenge.KindPayload.workouts))
            }
            if kind != nil {
                Stepper("\(target) times a week", value: $target, in: 1...7)
            }
            Button("Set Challenge") {
                save(kind.map { CrewChallenge(kind: $0, target: target) })
            }
            .disabled(kind == current?.kind && target == (current?.target ?? 3))
        }
        .onAppear {
            kind = current?.kind
            target = current?.target ?? 3
        }
    }
}
