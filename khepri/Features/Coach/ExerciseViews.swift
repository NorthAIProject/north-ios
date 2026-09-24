import NorthAPI
import NorthKit
import SwiftUI

/// The exercise a reply is about, inline under it: the movement playing,
/// its name and the muscles it works. Tap for the full card.
///
/// This is what Telegram sends as a GIF. Here it is drawn natively from the
/// server's path data, in the app's colours, sharp at any size.
struct ExerciseCard: View {
    let slug: String
    let onOpen: () -> Void
    @State private var detail: ExerciseDetail?
    @State private var failed = false

    private let coach: CoachServicing = CoachService()

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Group {
                    if let art = detail?.art {
                        ExerciseArtView(frames: art.frames, size: art.size)
                    } else {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.title)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(NorthColor.signal)
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text(detail?.name ?? slug.replacingOccurrences(of: "-", with: " ").capitalized)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let detail {
                        Text(Muscles.summary(detail))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else if !failed {
                        Text("Loading…").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .task {
            do { detail = try await coach.exercise(slug) } catch { failed = true }
        }
    }
}

/// The full exercise: large animation, how to do it, what it works, a video.
struct ExerciseSheet: View {
    let slug: String
    @State private var detail: ExerciseDetail?
    @State private var error: String?
    @State private var isPlaying = true
    @Environment(\.dismiss) private var dismiss

    private let coach: CoachServicing = CoachService()

    var body: some View {
        NavigationStack {
            ScrollView {
                if let detail {
                    content(detail)
                } else if let error {
                    ContentUnavailableView("Exercise unavailable", systemImage: "wifi.exclamationmark", description: Text(error))
                } else {
                    ProgressView().padding(.top, 48)
                }
            }
            .navigationTitle(detail?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .task {
            do { detail = try await coach.exercise(slug) } catch { self.error = error.localizedDescription }
        }
    }

    private func content(_ detail: ExerciseDetail) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if let art = detail.art {
                VStack(spacing: 8) {
                    ExerciseArtView(frames: art.frames, size: art.size, isPlaying: isPlaying)
                        .foregroundStyle(NorthColor.signal)
                        .frame(maxWidth: 320)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { isPlaying.toggle() }
                        .accessibilityLabel("\(detail.name) demonstration")
                        .accessibilityHint(isPlaying ? "Double-tap to pause" : "Double-tap to play")
                    Text(art.credit)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 8) {
                Tag(detail.difficulty.capitalized)
                Tag(detail.equipment == "none" ? "No equipment" : detail.equipment.capitalized)
                Tag(detail.category.replacingOccurrences(of: "_", with: " ").capitalized)
            }

            section("Works") {
                Text(Muscles.summary(detail))
            }

            // Some catalog entries carry artwork but no written steps.
            if !detail.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                section("How to") {
                    Text(detail.instructions)
                }
            }

            if let video = detail.videoUrl.flatMap(URL.init(string:)) {
                Link(destination: video) {
                    Label("Watch on YouTube", systemImage: "play.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(16)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.medium))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

private struct Tag: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemFill), in: .capsule)
    }
}

enum Muscles {
    /// "Chest · also triceps, shoulders"
    static func summary(_ detail: ExerciseDetail) -> String {
        let primary = detail.primaryMuscles.map(name).joined(separator: ", ")
        let secondary = detail.secondaryMuscles.map(name).joined(separator: ", ")
        switch (primary.isEmpty, secondary.isEmpty) {
        case (false, false): return "\(primary) · also \(secondary)"
        case (false, true): return primary
        case (true, false): return secondary
        case (true, true): return "Full body"
        }
    }

    private static func name(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
