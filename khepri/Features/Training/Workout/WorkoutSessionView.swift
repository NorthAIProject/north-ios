import NorthAPI
import NorthKit
import SwiftUI

/// The workout, full screen: the exercise moving, the set in hand, one big
/// button, and rest counted down between sets.
struct WorkoutSessionView: View {
    @State private var session: WorkoutSession
    @State private var confirmingEnd = false
    @State private var viewing: ExerciseSlugRoute?
    @State private var enteringSet = false
    @State private var imperial = false
    @Environment(\.dismiss) private var dismiss

    init(session: WorkoutSession) {
        _session = State(initialValue: session)
    }

    var body: some View {
        NavigationStack {
            Group {
                if session.phase == .finished {
                    WorkoutSummary(session: session) { dismiss() }
                } else {
                    inProgress
                }
            }
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if session.phase != .finished {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("End") { confirmingEnd = true }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(session.isPaused ? "Resume" : "Pause", systemImage: session.isPaused ? "play.fill" : "pause.fill") {
                            Task { session.isPaused ? await session.resume() : await session.pause() }
                        }
                    }
                }
            }
            .confirmationDialog("End this workout?", isPresented: $confirmingEnd, titleVisibility: .visible) {
                Button("Finish and Save") { Task { await session.finish() } }
                Button("Discard Workout", role: .destructive) {
                    Task {
                        await session.discard()
                        dismiss()
                    }
                }
                Button("Keep Going", role: .cancel) {}
            } message: {
                Text("\(session.completedSets) of \(session.totalSets) sets done.")
            }
            .sheet(item: $viewing) { route in ExerciseSheet(slug: route.slug) }
            .sheet(isPresented: $enteringSet) {
                if let exercise = session.current {
                    SetEntrySheet(exerciseName: exercise.name, setNumber: session.setNumber,
                                  suggestedWeightKg: session.suggestedWeightKg, suggestedReps: session.suggestedReps,
                                  lastTime: session.lastTimeForCurrent, imperial: imperial) { kg, reps in
                        Task { await session.completeSet(weightKg: kg, reps: reps) }
                    }
                }
            }
            .task { imperial = (try? await SettingsService().preferences().unitsSystem) == .imperial }
        }
        .interactiveDismissDisabled(session.phase != .finished)
        .onAppear { session.start() }
        // Rest ends by itself; the Live Activity counts the same end down.
        .task(id: session.restEndsAt) {
            guard let end = session.restEndsAt else { return }
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            session.endRest()
        }
        .sensoryFeedback(.success, trigger: session.completedSets)
        .sensoryFeedback(.impact(weight: .heavy), trigger: session.restEndsAt) { old, new in old != nil && new == nil }
    }

    private var inProgress: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let notice = session.notice {
                    Label(notice, systemImage: "exclamationmark.icloud")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
                }

                header

                if let exercise = session.current {
                    CurrentExercise(exercise: exercise, setNumber: session.setNumber, isResting: session.restEndsAt != nil) {
                        if let slug = exercise.catalogSlug { viewing = ExerciseSlugRoute(slug: slug) }
                    }
                }

                controls

                if session.restEndsAt == nil, let next = session.next {
                    Text(next.name == session.current?.name ? "Next: set \(session.setNumber + 1)" : "Next: \(next.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private var header: some View {
        HStack {
            Text("EXERCISE \(session.exerciseIndex + 1) OF \(session.exercises.count)")
                .northEyebrow()
            Spacer()
            Group {
                if session.isPaused {
                    Text(Duration.seconds(session.movingTime).formatted(.time(pattern: .minuteSecond)))
                } else {
                    Text(session.movingSince, style: .timer)
                }
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityLabel("Workout time")
        }
    }

    @ViewBuilder
    private var controls: some View {
        if let end = session.restEndsAt {
            VStack(spacing: 12) {
                Text("REST")
                    .northEyebrow(NorthColor.signal)
                Group {
                    if session.isPaused {
                        Text("Paused")
                    } else {
                        Text(timerInterval: Date.now...max(end, .now), countsDown: true)
                    }
                }
                .font(.north(size: 42, relativeTo: .largeTitle).weight(.light).monospacedDigit())
                .accessibilityIdentifier("rest-countdown")
                HStack(spacing: 12) {
                    Button("+15s") { session.extendRest(by: 15) }
                        .buttonStyle(.bordered)
                    Button("Skip Rest") { session.endRest() }
                        .northProminentButton()
                }
                .disabled(session.isPaused)
            }
            .frame(maxWidth: .infinity)
        } else {
            Button {
                // The weight comes before the next step: the set only counts
                // once it has been entered.
                enteringSet = true
            } label: {
                Text(session.isLastSet ? "Finish Workout" : "Done · Set \(session.setNumber)")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .northProminentButton()
            .controlSize(.large)
            .disabled(session.isPaused)
        }
    }
}

/// The exercise in hand: its animation, the prescription and a cue.
private struct CurrentExercise: View {
    let exercise: DayExercise
    let setNumber: Int
    let isResting: Bool
    let onShowDetail: () -> Void

    @State private var art: Components.Schemas.ExerciseArt?

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if let art {
                    // Still while resting: motion is for the set, not the pause.
                    ExerciseArtView(frames: art.frames, size: art.size, isPlaying: !isResting)
                } else {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(NorthColor.signal)
            .frame(maxWidth: 280, minHeight: 200)

            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text(exercise.name)
                        .font(.title2.weight(.semibold))
                    if exercise.catalogSlug != nil {
                        Button("How to", systemImage: "info.circle", action: onShowDetail)
                            .labelStyle(.iconOnly)
                    }
                }
                Text("\(isResting ? "Up next: set" : "Set") \(setNumber) of \(exercise.sets) · \(exercise.reps) reps")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let cue = exercise.formCues, !cue.isEmpty {
                    Text(cue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
        }
        .task(id: exercise.catalogSlug) {
            art = nil
            guard exercise.hasArt, let slug = exercise.catalogSlug else { return }
            art = try? await CoachService().exercise(slug).art
        }
    }
}

/// What was done, and whether the account has it.
private struct WorkoutSummary: View {
    let session: WorkoutSession
    let onDone: () -> Void
    var recaps: RecapServicing = RecapService()

    @Environment(AppRouter.self) private var router
    @State private var imperial = false
    /// The server's recap once it answers; until then, and if it cannot,
    /// the one built from what the phone saw.
    @State private var recap: WorkoutRecapModel?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(NorthColor.signal)
                        .padding(.top, 8)
                    Text("Workout done")
                        .font(.north(.title2).weight(.semibold))
                    statGrid
                    if session.recorded != nil || !session.logged.isEmpty {
                        WorkoutRecapCard(model: recap ?? .local(from: session), imperial: imperial)
                    }
                    if session.unsavedSets > 0 {
                        Text("\(session.unsavedSets) of your sets could not be saved to your account.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Group {
                        if session.recorded != nil {
                            Text("Saved to your activity. Your coach will see it.")
                        } else if let notice = session.notice {
                            Text(notice)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            VStack(spacing: 8) {
                Button(action: onDone) {
                    Text("Done").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .northProminentButton()
                .controlSize(.large)
                if session.recorded != nil {
                    Button("See Progress") {
                        onDone()
                        router.open(.tab(.progress))
                    }
                    .font(.subheadline)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .task { imperial = (try? await SettingsService().preferences().unitsSystem) == .imperial }
        .task(id: session.recorded?.id) { await loadRecap() }
    }

    /// Two columns, so a long duration or a five-digit volume shrinks instead
    /// of turning into "54:3…" and "11 5…".
    private var statGrid: some View {
        let items = headlineStats
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { start in
                GridRow {
                    ForEach(start..<min(start + 2, items.count), id: \.self) { index in
                        stat(items[index].value, items[index].label)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var headlineStats: [(value: String, label: String)] {
        var items: [(value: String, label: String)] = [
            (value: Duration.seconds(session.movingTime).formatted(.time(pattern: .minuteSecond)), label: "TIME"),
            (value: "\(session.completedSets)/\(session.totalSets)", label: "SETS")
        ]
        if session.volumeKg > 0 {
            let lifted = LiftMath.display(session.volumeKg, imperial: imperial)
                .formatted(.number.precision(.fractionLength(0)).grouping(.automatic))
            items.append((value: lifted, label: imperial ? "LB LIFTED" : "KG LIFTED"))
        }
        if let calories = session.recorded?.caloriesBurned {
            items.append((value: calories.formatted(.number.precision(.fractionLength(0)).grouping(.automatic)), label: "KCAL"))
        }
        return items
    }

    /// Asks the server for the recap of the saved session. A failure keeps
    /// the local one: the numbers the phone counted are still true.
    private func loadRecap() async {
        guard let id = session.recorded?.id, session.recorded?.status == .completed else { return }
        if let fetched = try? await recaps.recap(sessionID: id) {
            recap = WorkoutRecapModel(fetched)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .northDisplayNumber(.title2)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label).northEyebrow()
        }
        .accessibilityElement(children: .combine)
    }
}
