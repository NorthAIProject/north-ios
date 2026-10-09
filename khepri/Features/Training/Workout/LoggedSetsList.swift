import NorthKit
import SwiftUI

/// The sets of the exercise in hand done so far, under the big button.
/// Warm-ups are set apart: smaller, dimmed and marked "W", since they do not
/// count toward the plan's sets or the workout's volume.
struct LoggedSetsList: View {
    let sets: [WorkoutSession.LoggedSet]
    let imperial: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DONE")
                .northEyebrow()
            ForEach(sets) { set in
                LoggedSetRow(entry: set, imperial: imperial)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }
}

private struct LoggedSetRow: View {
    let entry: WorkoutSession.LoggedSet
    let imperial: Bool

    private var isWarmup: Bool { entry.kind == .warmup }

    var body: some View {
        HStack(spacing: 12) {
            badge
            Text(load)
                .font(isWarmup ? .subheadline.monospacedDigit() : .body.weight(.medium).monospacedDigit())
                .foregroundStyle(isWarmup ? .secondary : .primary)
            Spacer()
            if let rir = entry.rir {
                Text("RIR \(RepsInReserve.label(rir))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// The set's number for a work set; a letter for the others.
    private var badge: some View {
        Group {
            switch entry.kind {
            case .work: Text("\(entry.setNumber)")
            case .warmup: Text("W")
            case .drop: Text("D")
            }
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .frame(width: 24, height: 24)
        .foregroundStyle(isWarmup ? AnyShapeStyle(.secondary) : AnyShapeStyle(NorthColor.signal))
        .background {
            if isWarmup {
                Circle().strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            } else {
                Circle().fill(NorthColor.signal.opacity(0.15))
            }
        }
        .accessibilityHidden(true)
    }

    private var load: String {
        guard entry.weightKg > 0 else { return String(localized: "BW × \(entry.reps)") }
        let shown = LiftMath.display(entry.weightKg, imperial: imperial)
        return "\(shown.formatted()) \(imperial ? "lb" : "kg") × \(entry.reps)"
    }

    private var accessibilityText: String {
        let kind = switch entry.kind {
        case .work: String(localized: "Set \(entry.setNumber)")
        case .warmup: String(localized: "Warm-up")
        case .drop: String(localized: "Drop set")
        }
        let reserve = entry.rir.map { String(localized: ", \(RepsInReserve.label($0)) in reserve") } ?? ""
        return "\(kind): \(load)\(reserve)"
    }
}
