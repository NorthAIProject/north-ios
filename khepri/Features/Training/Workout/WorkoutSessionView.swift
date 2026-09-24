import NorthAPI
import NorthKit
import SwiftUI

/// The workout, full screen: the exercise moving, the set in hand, one big
/// button, and rest counted down between sets.
struct WorkoutSessionView: View {
    @State private var session: WorkoutSession
    @State private var confirmingEnd = false
    @State private var viewing: ExerciseSlugRoute?
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
                .font(.caption.weight(.medium))
                .tracking(1.5)
                .foregroundStyle(.secondary)
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
                    .font(.caption.weight(.medium))
                    .tracking(1.5)
                    .foregroundStyle(NorthColor.signal)
                Group {
                    if session.isPaused {
                        Text("Paused")
                    } else {
                        Text(timerInterval: Date.now...max(end, .now), countsDown: true)
                    }
                }
                .font(.system(size: 42, weight: .light).monospacedDigit())
                .accessibilityIdentifier("rest-countdown")
                HStack(spacing: 12) {
                    Button("+15s") { session.extendRest(by: 15) }
                        .buttonStyle(.bordered)
                    Button("Skip Rest") { session.endRest() }
                        .buttonStyle(.borderedProminent)
                }
                .disabled(session.isPaused)
            }
            .frame(maxWidth: .infinity)
        } else {
            Button {
                Task { await session.completeSet() }
            } label: {
                Text(session.isLastSet ? "Finish Workout" : "Done · Set \(session.setNumber)")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
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

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(NorthColor.signal)
            VStack(spacing: 8) {
                Text("Workout done")
                    .font(.title2.weight(.semibold))
                Text(session.title)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 32) {
                stat(Duration.seconds(session.movingTime).formatted(.time(pattern: .minuteSecond)), "TIME")
                stat("\(session.completedSets)/\(session.totalSets)", "SETS")
                if let calories = session.recorded?.caloriesBurned {
                    stat(calories.formatted(.number.precision(.fractionLength(0))), "KCAL")
                }
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
            Spacer()
            Button(action: onDone) {
                Text("Done").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(20)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 24, weight: .light).monospacedDigit())
            Text(label).font(.caption.weight(.medium)).tracking(1.5).foregroundStyle(.secondary)
        }
    }
}
