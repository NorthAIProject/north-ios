import NorthAPI
import SwiftUI

struct TodayView: View {
    let snapshot: TodaySnapshot
    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let nextStep = snapshot.nextStep {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(nextStep.eyebrow.uppercased())
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(nextStep.title)
                                .font(.title2.weight(.semibold))
                            Text(nextStep.body)
                                .foregroundStyle(.secondary)
                            Button(nextStep.cta) {}
                                .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                    }

                    HStack(spacing: 12) {
                        MetricView(title: "Streak", value: "\(snapshot.streak) days")
                        MetricView(title: "Check-in", value: snapshot.checkedInToday ? "Done" : "Open")
                    }

                    SectionCard(title: "Goals") {
                        if snapshot.goals.isEmpty {
                            Text("No active goals yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(snapshot.goals, id: \.id) { goal in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(goal.title)
                                        Text(goal.category.capitalized)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let progress = goal.progress {
                                        Text("\(progress)%")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                }
                            }
                        }
                    }

                    SectionCard(title: "Today") {
                        HStack {
                            Text("Water")
                            Spacer()
                            Text("\(snapshot.hydration.todayML) / \(snapshot.hydration.targetML) ml")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Sleep")
                            Spacer()
                            Text(snapshot.sleep.logged ? "\(snapshot.sleep.durationMinutes) min" : "Not logged")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !snapshot.timeline.isEmpty {
                        SectionCard(title: "Recent activity") {
                            ForEach(snapshot.timeline, id: \.at) { entry in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.title)
                                    if let detail = entry.detail, !detail.isEmpty {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out", role: .destructive, action: onSignOut)
                }
            }
        }
    }
}

private struct MetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
