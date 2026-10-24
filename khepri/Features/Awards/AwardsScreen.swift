import NorthAPI
import NorthKit
import SwiftUI

/// Your badges: the ones you have earned, and how far along the rest are.
/// Badges are for the doing; they carry no XP.
struct AwardsScreen: View {
    var service: AwardsServicing = AwardsService()

    @State private var model: AwardsModel?
    @State private var error: String?
    @State private var shown: Award?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else if let error {
                ContentUnavailableView {
                    Label("Awards did not load", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Awards")
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $shown) { award in
            AwardDetailSheet(award: award)
                .presentationDetents([.medium, .large])
        }
    }

    private func content(_ model: AwardsModel) -> some View {
        List {
            if let error { ErrorRow(error) }
            if let challenge = model.challenge { challengeSection(challenge) }
            Section {
                if model.earned.isEmpty {
                    Text("Finish a workout, check in or hit a goal, and your first badge lands here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.earned) { row in awardButton(row) }
            } header: {
                Text("Earned · \(model.badgesEarned) of \(model.total)")
            }
            if !model.locked.isEmpty {
                Section("Still to Earn") {
                    ForEach(model.locked) { row in awardButton(row) }
                }
            }
        }
    }

    private func challengeSection(_ challenge: AwardsModel.MonthlyChallenge) -> some View {
        Section("This Month") {
            MonthlyChallengeCard(challenge: challenge)
                .accessibilityIdentifier("awards.monthlyChallenge")
        }
    }

    private func awardButton(_ row: AwardsModel.Row) -> some View {
        Button { shown = row.award } label: {
            AwardRow(row: row)
        }
        .foregroundStyle(.primary)
    }

    private func load() async {
        do {
            async let unseen = service.unseen()
            let overview = try await service.awards()
            // Celebration state is a nicety: a failure leaves nothing marked new.
            model = AwardsModel(overview, unseen: (try? await unseen) ?? [])
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension Award: @retroactive Identifiable {}

struct AwardRow: View {
    let row: AwardsModel.Row

    var body: some View {
        HStack(spacing: 12) {
            AwardCoin(award: row.award, size: 48, locked: !row.isEarned)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.award.name).font(.body.weight(.medium))
                    if row.isNew {
                        Text("New")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(NorthColor.signal.opacity(0.18), in: .capsule)
                            .foregroundStyle(NorthColor.signal)
                    }
                }
                Text(row.award.description).font(.caption).foregroundStyle(.secondary)
                if let text = row.progressText {
                    ProgressView(value: row.fraction)
                    Text(text).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
