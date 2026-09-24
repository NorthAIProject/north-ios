import NorthAPI
import NorthKit
import SwiftUI

/// Choose an exercise: suggestions that fit, or a search of the library.
struct ExercisePicker: View {
    let title: String
    let suggestions: () async throws -> [ExerciseSummary]
    let search: (String) async throws -> [ExerciseSummary]
    let onPick: (String) -> Void

    @State private var query = ""
    @State private var suggested: [ExerciseSummary] = []
    @State private var results: [ExerciseSummary] = []
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section("Suggested") {
                        ForEach(suggested, id: \.slug) { row($0) }
                    }
                } else {
                    ForEach(results, id: \.slug) { row($0) }
                }
                if let error { ErrorRow(error) }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search the library")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task {
                do { suggested = try await suggestions() } catch { self.error = error.localizedDescription }
            }
            // Debounced by the task restarting on each keystroke.
            .task(id: query) {
                guard !query.isEmpty else { return }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                do { results = try await search(query) } catch { self.error = error.localizedDescription }
            }
        }
    }

    private func row(_ exercise: ExerciseSummary) -> some View {
        Button {
            onPick(exercise.slug)
            dismiss()
        } label: {
            ExerciseSummaryRow(exercise: exercise)
        }
        .buttonStyle(.plain)
    }
}

/// The whole library, to browse or look something up.
struct ExerciseLibrary: View {
    let service: TrainingServicing
    @State private var query = ""
    @State private var muscle: String?
    @State private var results: [ExerciseSummary] = []
    @State private var error: String?
    @State private var viewing: ExerciseSlugRoute?

    private let muscles = ["chest", "back", "shoulders", "biceps", "triceps", "core", "quads", "hamstrings", "glutes", "calves"]

    var body: some View {
        List {
            ForEach(results, id: \.slug) { exercise in
                Button { viewing = ExerciseSlugRoute(slug: exercise.slug) } label: {
                    ExerciseSummaryRow(exercise: exercise)
                }
                .buttonStyle(.plain)
            }
            if let error { ErrorRow(error) }
        }
        .navigationTitle("Library")
        // Search is what a library is for, so the field is always showing.
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Push-up, squat, row…")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Muscle", selection: $muscle) {
                        Text("All muscles").tag(String?.none)
                        ForEach(muscles, id: \.self) { Text($0.capitalized).tag(Optional($0)) }
                    }
                } label: {
                    Label("Muscle", systemImage: muscle == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .task(id: "\(query)|\(muscle ?? "")") {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                results = try await service.searchExercises(query, muscle: muscle)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
        .sheet(item: $viewing) { route in ExerciseSheet(slug: route.slug) }
    }
}

struct ExerciseSummaryRow: View {
    let exercise: ExerciseSummary

    var body: some View {
        HStack(spacing: 12) {
            ExerciseThumbnail(slug: exercise.hasArt ? exercise.slug : nil)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                Text([exercise.primaryMuscles.map(\.capitalized).joined(separator: ", "),
                      exercise.equipment == "none" ? "no equipment" : exercise.equipment]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
