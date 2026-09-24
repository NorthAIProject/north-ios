import NorthAPI
import NorthKit
import SwiftUI

/// One training day: when it starts, and its exercises to reorder, swap,
/// adjust or remove.
struct DayView: View {
    let store: TrainingStore
    let dayIndex: Int

    @State private var picking: PickerPurpose?
    @State private var adjusting: IndexedExercise?
    @State private var viewing: ExerciseSlugRoute?
    @State private var workout: WorkoutSession?
    @Environment(AppRouter.self) private var router

    /// A new start time begins at the one the other days use most, so a
    /// plan's sessions line up without adjusting each; 07:00 otherwise.
    private var suggestedStart: String {
        let times = (store.plan?.days ?? []).compactMap(\.startTime)
        let counts = Dictionary(times.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { $0.value < $1.value }?.key ?? "07:00"
    }

    private var day: TrainingDay? {
        guard let plan = store.plan, plan.days.indices.contains(dayIndex) else { return nil }
        return plan.days[dayIndex]
    }

    var body: some View {
        if let day {
            List {
                if let notice = store.notice {
                    Section { Label(notice, systemImage: "arrow.triangle.2.circlepath").font(.subheadline) }
                }

                Section {
                    Button {
                        startWorkout(day)
                    } label: {
                        Label("Start Workout", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .northProminentButton()
                    .disabled(day.exercises.isEmpty)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                StartTimeSection(startTime: day.startTime, suggested: suggestedStart, isSaving: store.isEditing) { time in
                    Task { await store.setStartTime(day: dayIndex, to: time) }
                }

                Section {
                    ForEach(Array(day.exercises.enumerated()), id: \.offset) { index, exercise in
                        ExerciseRow(exercise: exercise)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let slug = exercise.catalogSlug { viewing = ExerciseSlugRoute(slug: slug) }
                            }
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    Task { await store.remove(day: dayIndex, index: index) }
                                }
                                Button("Swap") { picking = .swap(index) }
                                    .tint(NorthColor.agent)
                            }
                            .contextMenu {
                                Button("Change Sets & Reps", systemImage: "slider.horizontal.3") {
                                    adjusting = IndexedExercise(index: index, exercise: exercise)
                                }
                                Button("Swap Exercise", systemImage: "arrow.left.arrow.right") { picking = .swap(index) }
                                if index > 0 {
                                    Button("Move Up", systemImage: "arrow.up") {
                                        Task { await store.move(day: dayIndex, index: index, up: true) }
                                    }
                                }
                                if index < day.exercises.count - 1 {
                                    Button("Move Down", systemImage: "arrow.down") {
                                        Task { await store.move(day: dayIndex, index: index, up: false) }
                                    }
                                }
                                Button("Remove", systemImage: "trash", role: .destructive) {
                                    Task { await store.remove(day: dayIndex, index: index) }
                                }
                            }
                    }
                    Button("Add Exercise", systemImage: "plus") { picking = .add }
                } header: {
                    Text("Exercises")
                } footer: {
                    Text("Swipe to swap or remove. Touch and hold for sets, reps and order.")
                }
            }
            .navigationTitle(day.weekday)
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if store.isEditing { ProgressView().padding().background(.regularMaterial, in: .rect(cornerRadius: 10)) }
            }
            .sheet(item: $picking) { purpose in
                ExercisePicker(
                    title: purpose == .add ? "Add Exercise" : "Swap Exercise",
                    suggestions: {
                        guard let plan = store.plan else { return [] }
                        switch purpose {
                        case .add: return try await store.service.suggestions(plan: plan.id, day: dayIndex)
                        case .swap(let index): return try await store.service.replacements(plan: plan.id, day: dayIndex, index: index)
                        }
                    },
                    search: { query in try await store.service.searchExercises(query, muscle: nil) }
                ) { slug in
                    Task {
                        switch purpose {
                        case .add: await store.add(slug, to: dayIndex)
                        case .swap(let index): await store.swap(day: dayIndex, index: index, for: slug)
                        }
                    }
                }
            }
            .sheet(item: $adjusting) { item in
                PrescriptionSheet(exercise: item.exercise) { sets, reps, rest in
                    Task { await store.setPrescription(day: dayIndex, index: item.index, sets: sets, reps: reps, restSeconds: rest) }
                }
            }
            .sheet(item: $viewing) { route in ExerciseSheet(slug: route.slug) }
            .fullScreenCover(item: $workout) { session in WorkoutSessionView(session: session) }
            // The reminder's Start Workout button.
            .onAppear {
                guard router.startsWorkout else { return }
                router.startsWorkout = false
                startWorkout(day)
            }
        } else {
            ContentUnavailableView("This day is no longer in the plan", systemImage: "calendar.badge.exclamationmark")
        }
    }
}

extension DayView {
    private func startWorkout(_ day: TrainingDay) {
        guard workout == nil, !day.exercises.isEmpty else { return }
        workout = WorkoutSession(
            title: "\(day.weekday) · \(day.focus)",
            day: day,
            service: ActivityService(),
            live: WorkoutLiveActivityController(),
            health: HealthWorkoutWriter()
        )
    }
}

private enum PickerPurpose: Identifiable, Hashable {
    case add
    case swap(Int)
    var id: String { if case .swap(let i) = self { "swap-\(i)" } else { "add" } }
}

private struct IndexedExercise: Identifiable {
    let index: Int
    let exercise: DayExercise
    var id: Int { index }
}

struct ExerciseSlugRoute: Identifiable {
    let slug: String
    var id: String { slug }
}

/// When the session starts, which is when the reminder is timed from.
private struct StartTimeSection: View {
    let startTime: String?
    let suggested: String
    let isSaving: Bool
    let onChange: (String?) -> Void

    @State private var draft = Date.now

    var body: some View {
        Section {
            Toggle("Set a start time", isOn: Binding(
                get: { startTime != nil },
                set: { on in onChange(on ? suggested : nil) }
            ))
            .disabled(isSaving)
            if startTime != nil {
                DatePicker("Starts at", selection: $draft, displayedComponents: .hourAndMinute)
                    .onChange(of: draft) { _, new in
                        let value = ClockTime.string(from: new)
                        if value != startTime { onChange(value) }
                    }
            }
        } footer: {
            if startTime != nil, WorkoutReminderSettings.enabled {
                Text("You'll get a reminder \(WorkoutReminderSettings.leadMinutes) minutes before, with a button to start. The web plan shows the same time.")
            } else {
                Text("With a start time, your iPhone reminds you shortly before.")
            }
        }
        .onAppear { if let startTime { draft = ClockTime.date(from: startTime) } }
        .onChange(of: startTime) { _, new in if let new { draft = ClockTime.date(from: new) } }
    }
}

private struct ExerciseRow: View {
    let exercise: DayExercise

    var body: some View {
        HStack(spacing: 12) {
            ExerciseThumbnail(slug: exercise.hasArt ? exercise.catalogSlug : nil)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                Text("\(exercise.sets) × \(exercise.reps) · rest \(exercise.restSeconds)s")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let cue = exercise.formCues, !cue.isEmpty {
                    Text(cue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

/// A still pose for lists: the first frame, drawn from the shared cache.
struct ExerciseThumbnail: View {
    let slug: String?
    @State private var art: Components.Schemas.ExerciseArt?

    var body: some View {
        Group {
            if let art {
                ExerciseArtView(frames: art.frames, size: art.size, isPlaying: false)
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(NorthColor.signal)
        .task(id: slug) {
            guard let slug else { return }
            art = try? await CoachService().exercise(slug).art
        }
    }
}

/// Sets, reps and rest for one exercise.
private struct PrescriptionSheet: View {
    let exercise: DayExercise
    let onSave: (Int, String, Int) -> Void
    @State private var sets = 3
    @State private var reps = ""
    @State private var rest = 90
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Stepper("\(sets) sets", value: $sets, in: 1...12)
                TextField("Reps, e.g. 8-12 or AMRAP", text: $reps)
                Stepper("Rest \(rest)s", value: $rest, in: 0...600, step: 15)
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(sets, reps, rest)
                        dismiss()
                    }
                    .disabled(reps.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                sets = exercise.sets
                reps = exercise.reps
                rest = exercise.restSeconds
            }
        }
        .presentationDetents([.medium])
    }
}
