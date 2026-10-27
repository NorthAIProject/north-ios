import NorthAPI
import NorthKit
import SwiftUI

/// What saving today's check-in just earned. Only the save that created the
/// day's check-in has one: an edit has been celebrated already.
struct CheckInCelebration: Identifiable, Equatable {
    struct Moment: Equatable {
        let kind: String
        let title: String
        let body: String
    }

    let id = UUID()
    let moment: Moment?

    init?(saved: SavedCheckIn) {
        guard saved.value2.created else { return nil }
        moment = saved.value2.moment.map { Moment(kind: $0.kind, title: $0.title, body: $0.body) }
    }

    /// The symbol for a moment's kind; a kind this build does not know gets a
    /// generic one.
    static func symbol(for kind: String) -> String {
        switch kind {
        case "streak": "flame.fill"
        case "perfect_week": "star.fill"
        case "rest_day_earned": "bed.double.fill"
        case "comeback": "sunrise.fill"
        default: "sparkles"
        }
    }
}

/// The coach's note under today's check-in, as the screen shows it.
struct CheckInReplyNote: Equatable {
    let text: String
    let isPattern: Bool

    init?(_ reply: CheckInReply?) {
        guard let reply, !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        text = reply.text
        isPattern = reply.kind == "pattern"
    }
}

/// The card a moment earns: Khepri's mark, the moment's symbol, a title and
/// a line.
struct CheckInMomentCard: View {
    let moment: CheckInCelebration.Moment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // The mark carries fixed brand colour; never tint it.
            NorthBrand.mark
                .resizable()
                .scaledToFit()
                .padding(6)
                .frame(width: 44, height: 44)
                .background(Color(.secondarySystemFill), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Label(moment.title, systemImage: CheckInCelebration.symbol(for: moment.kind))
                    .font(.headline)
                    .foregroundStyle(NorthColor.ember)
                Text(moment.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Monday to Sunday, a dot a day. A rest day is a ring; a perfect week so far
/// turns the checked days ember. A past day without a check-in is drawn like
/// any empty day, never as missed.
struct CheckInWeekDots: View {
    let week: [CheckInDayState]
    let perfect: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(week.enumerated()), id: \.offset) { _, state in
                dot(state).frame(width: 10, height: 10)
            }
            if perfect {
                Text("Perfect week so far")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(NorthColor.ember)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(week.count(where: { $0 == .checked })) of 7 days checked in this week"))
    }

    @ViewBuilder private func dot(_ state: CheckInDayState) -> some View {
        switch state {
        case .checked: Circle().fill(perfect ? NorthColor.ember : NorthColor.signal)
        case .rest: Circle().strokeBorder(NorthColor.signal, lineWidth: 2)
        case .today: Circle().strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
        case .upcoming: Circle().fill(Color.secondary.opacity(0.15))
        case .none: Circle().fill(Color.secondary.opacity(0.3))
        }
    }
}

/// The coach's note, or a placeholder while it is written. Tapping it opens
/// the coach.
struct CheckInReplyBubble: View {
    /// Nil while the note is being written.
    let note: CheckInReplyNote?
    let open: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 4) {
                if note?.isPattern == true {
                    Text("Pattern unlocked")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(NorthColor.signal)
                }
                Text(note?.text ?? "The coach is reading your check-in and writing a note.")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .redacted(reason: note == nil ? .placeholder : [])
                    .opacity(note == nil && dim ? 0.4 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(note == nil)
        .accessibilityHint(Text("Opens the coach"))
        .task(id: note == nil) {
            guard note == nil, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever()) { dim = true }
        }
    }
}
