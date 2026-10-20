import NorthAPI
import NorthKit
import SwiftUI

/// Progress checks: photos, weight and a few measurements on a cadence the
/// person picks, the way a trainer would take them. The same page as the
/// web's /app/progress. A tracking tool, not a medical one: no judgement in
/// the words, and estimates are labelled as estimates.
struct ProgressCheckScreen: View {
    @State private var store: ProgressCheckStore
    @State private var addingCheck = false
    @State private var deleting: ProgressCheck?

    init(service: ProgressCheckServicing = ProgressCheckService()) {
        _store = State(initialValue: ProgressCheckStore(service: service))
    }

    var body: some View {
        List {
            Section {
                Text("Photos, weight and a few measurements on a schedule you choose, the way a trainer would take them. The figure on Today takes its shape from your latest check.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if store.schedule?.due == true {
                    Label("A progress check is due. Whenever suits you today.", systemImage: "calendar.badge.clock")
                        .accessibilityIdentifier("progress-due")
                }
                Button {
                    addingCheck = true
                } label: {
                    Label("New check", systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("progress-new")
            }
            if let error = store.error {
                ErrorRow(error)
            }
            if let list = store.list, list.comparison != nil || list.canCompare {
                ProgressComparisonSection(store: store)
            }
            ProgressReminderSection(store: store)
            Section("Your checks") {
                if store.list != nil, store.checks.isEmpty {
                    ContentUnavailableView(
                        "No checks yet",
                        systemImage: "ruler",
                        description: Text("Your first one sets the starting point; each one after shows how things moved.")
                    )
                }
                ForEach(store.checks, id: \.id) { check in
                    ProgressCheckRow(check: check, older: store.older(than: check))
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = check }
                        }
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = check }
                        }
                }
            }
        }
        .navigationTitle("Progress check")
        .task { await store.load() }
        .refreshable { await store.load() }
        .sheet(isPresented: $addingCheck) {
            NewProgressCheckSheet(store: store)
        }
        .confirmationDialog(
            "Delete this check?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { check in
            Button("Delete", role: .destructive) { Task { await store.delete(check) } }
        } message: { _ in
            Text("Its photos are deleted too. This cannot be undone.")
        }
    }
}

/// The reminder's cadence. Saved as soon as it changes, like the web's
/// radios; "Off" turns the reminder off.
private struct ProgressReminderSection: View {
    let store: ProgressCheckStore

    private static let cadences: [(value: String, title: LocalizedStringKey)] = [
        ("weekly", "Weekly"), ("biweekly", "Every 2 weeks"), ("monthly", "Monthly"), ("", "Off")
    ]

    var body: some View {
        Section {
            Picker("Reminder", selection: Binding(
                get: { store.schedule?.cadence ?? "" },
                set: { cadence in Task { await store.setCadence(cadence) } }
            )) {
                ForEach(Self.cadences, id: \.value) { cadence in
                    Text(cadence.title).tag(cadence.value)
                }
            }
            .accessibilityIdentifier("progress-cadence")
        } footer: {
            if let next = store.schedule?.nextDueOn.flatMap({ CalendarDay.date(from: $0) }) {
                Text("Next check: \(next.formatted(.dateTime.day().month(.wide))).")
            } else {
                Text("No reminder set.")
            }
        }
    }
}

/// One saved check: its date, its numbers against the check before, and its
/// photos.
private struct ProgressCheckRow: View {
    let check: ProgressCheck
    let older: ProgressCheck?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ProgressCheckText.date(check.measuredOn)).font(.headline)
                Spacer()
                if check.isAssisted {
                    Text("Estimated, then confirmed")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(Capsule().stroke(.secondary.opacity(0.5)))
                }
            }
            let chips = check.chips(since: older)
            if !chips.isEmpty {
                WrappingStack(spacing: 6) {
                    ForEach(chips) { chip in
                        ProgressChipView(chip: chip)
                    }
                }
            }
            if !check.photos.isEmpty {
                HStack(spacing: 8) {
                    ForEach(check.photos, id: \.pose) { photo in
                        ProgressPhotoThumbnail(url: photo.url)
                            .frame(width: 60, height: 80)
                            .accessibilityLabel(ProgressPose(rawValue: photo.pose)?.title ?? photo.pose)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("progress-check")
    }
}

private struct ProgressChipView: View {
    let chip: ProgressChip

    var body: some View {
        HStack(spacing: 4) {
            Text(chip.field.title).font(.caption).foregroundStyle(.secondary)
            Text("\(ProgressCheckText.number(chip.value)) \(chip.field.unit)").monospacedDigit()
            if let delta = chip.delta {
                Text(ProgressCheckText.delta(delta)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if chip.carried {
                Text("· last known").font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(NorthColor.surface, in: .rect(cornerRadius: NorthRadius.small))
    }
}

/// A private photo from its signed link.
struct ProgressPhotoThumbnail: View {
    let url: String

    var body: some View {
        AsyncImage(url: URL(string: url)) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Rectangle().fill(NorthColor.surface)
        }
        .clipShape(.rect(cornerRadius: NorthRadius.small))
    }
}

/// The page's dates and numbers, as the person reads them.
enum ProgressCheckText {
    static func date(_ day: String) -> String {
        CalendarDay.date(from: day)?.formatted(.dateTime.day().month(.abbreviated).year()) ?? day
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// A change with its sign; the minus is a true minus, as on the web.
    static func delta(_ change: Double) -> String {
        change > 0 ? "+\(number(change))" : "−\(number(-change))"
    }

    static func confidence(_ value: String) -> String {
        switch value {
        case "high": String(localized: "high confidence")
        case "medium": String(localized: "medium confidence")
        default: String(localized: "low confidence")
        }
    }
}
