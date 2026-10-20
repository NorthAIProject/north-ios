import NorthAPI
import NorthKit
import SwiftUI

extension CrewMessage: @retroactive Identifiable {}

extension CrewMessage {
    /// The author's name, or their handle when the name is missing.
    var authorName: String {
        let person = author?.value1
        return person?.name ?? person?.handle ?? ""
    }
}

/// One crew message: avatar, name and time over the body, with its quote,
/// reactions and pin. Long-press for the menu; swipe right to reply.
struct CrewMessageRow: View {
    let message: CrewMessage
    let actions: [CrewMessageAction]
    let onAction: (CrewMessageAction) -> Void
    /// Toggles the reader's reaction with this key.
    let onReact: (String) -> Void

    @State private var swipe: CGFloat = 0
    private let replyDistance: CGFloat = 60

    var body: some View {
        switch message.kind {
        case "system":
            Text(message.body ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        case "text":
            content
                .contextMenu { menu }
                .offset(x: swipe)
                .background(alignment: .leading) { replyHint }
                .simultaneousGesture(replySwipe, including: actions.contains(.reply) ? .all : .subviews)
                .accessibilityActions {
                    if actions.contains(.reply) {
                        Button("Reply") { onAction(.reply) }
                    }
                }
        default:
            // A kind this build does not know: say so rather than guess.
            header(details: Text("Update Khepri to see this").italic().foregroundStyle(.secondary))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let quote = message.replyTo?.value1 {
                CrewQuoteView(quote: quote).padding(.leading, 46)
            }
            header(details: details)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.mentionsMe == true ? NorthColor.signal.opacity(0.08) : .clear)
        .contentShape(.rect)
    }

    private func header(details: some View) -> some View {
        HStack(alignment: .top, spacing: 10) {
            CrewAvatar(name: message.authorName)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(message.authorName).font(.subheadline.weight(.semibold))
                    if let date = message.createdAt {
                        Text(CrewTime.short(date)).font(.caption).foregroundStyle(.secondary)
                    }
                    if message.pinned == true {
                        Label("Pinned", systemImage: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                }
                details
            }
        }
    }

    @ViewBuilder private var details: some View {
        if message.deleted == true {
            Text("This message was deleted.").italic().foregroundStyle(.secondary)
        } else {
            CrewMessageText(text: message.body ?? "", edited: message.edited == true)
            let reactions = (message.reactions ?? []).filter { CrewEmoji.glyph($0.emoji) != nil && $0.count >= 1 }
            if !reactions.isEmpty {
                WrappingStack(spacing: 6) {
                    ForEach(reactions, id: \.emoji) { reaction in
                        CrewReactionPill(reaction: reaction) { onReact(reaction.emoji) }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder private var menu: some View {
        if actions.contains(.react) {
            ControlGroup {
                ForEach(CrewEmoji.keys, id: \.self) { key in
                    Button(CrewEmoji.glyph(key) ?? key) { onReact(key) }
                }
            } label: {
                Text("React")
            }
            .controlGroupStyle(.palette)
        }
        ForEach(actions.filter { $0 != .react }, id: \.self) { action in
            CrewMessageMenuItem(action: action, authorName: message.authorName) { onAction(action) }
        }
    }

    // MARK: Swipe to reply

    private var replySwipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { drag in
                // Only a mostly sideways drag to the right; vertical drags scroll.
                let width = drag.translation.width
                guard width > 0, width > abs(drag.translation.height) * 2 else { return }
                swipe = min(width, replyDistance * 1.3)
            }
            .onEnded { _ in
                if swipe >= replyDistance { onAction(.reply) }
                withAnimation(.spring(duration: 0.25)) { swipe = 0 }
            }
    }

    private var replyHint: some View {
        Image(systemName: "arrowshape.turn.up.left.fill")
            .foregroundStyle(swipe >= replyDistance ? NorthColor.signal : .secondary)
            .opacity(min(swipe / replyDistance, 1))
            .padding(.leading, 16)
            .accessibilityHidden(true)
    }
}

/// One entry of the message menu.
private struct CrewMessageMenuItem: View {
    let action: CrewMessageAction
    let authorName: String
    let run: () -> Void

    var body: some View {
        switch action {
        case .react: EmptyView()
        case .reply: Button("Reply", systemImage: "arrowshape.turn.up.left", action: run)
        case .copy: Button("Copy", systemImage: "doc.on.doc", action: run)
        case .edit: Button("Edit", systemImage: "pencil", action: run)
        case .pin: Button("Pin", systemImage: "pin", action: run)
        case .unpin: Button("Unpin", systemImage: "pin.slash", action: run)
        case .delete: Button("Delete", systemImage: "trash", role: .destructive, action: run)
        case .report: Button("Report", systemImage: "exclamationmark.bubble", action: run)
        case .block: Button("Block \(authorName)", systemImage: "hand.raised", role: .destructive, action: run)
        }
    }
}

/// A message body with `@handle` runs in the signal colour and the
/// "(edited)" mark after it.
struct CrewMessageText: View {
    let text: String
    var edited = false

    var body: some View {
        Text(attributed)
            .font(.body)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        var styled = AttributedString(text)
        for run in CrewMention.runs(in: text) {
            guard let range = Range(run, in: styled) else { continue }
            styled[range].foregroundColor = NorthColor.signal
            styled[range].font = .body.weight(.medium)
        }
        if edited {
            var mark = AttributedString(" ")
            var label = AttributedString(localized: "(edited)")
            label.font = .caption
            label.foregroundColor = Color.secondary
            mark.append(label)
            styled.append(mark)
        }
        return styled
    }
}

/// The message a reply answers, or a placeholder when it is gone.
struct CrewQuoteView: View {
    let quote: Components.Schemas.CrewQuote

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrowshape.turn.up.left").imageScale(.small)
            if quote.unavailable == true {
                Text("This message isn't available.").italic()
            } else {
                Text(quote.authorName ?? "").fontWeight(.medium)
                Text(quote.excerpt ?? "").lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// A reaction and its count; filled when it is the reader's own.
private struct CrewReactionPill: View {
    let reaction: Components.Schemas.CrewReaction
    let toggle: () -> Void

    var body: some View {
        let mine = reaction.mine == true
        Button(action: toggle) {
            HStack(spacing: 4) {
                Text(CrewEmoji.glyph(reaction.emoji) ?? "")
                Text(reaction.count, format: .number).monospacedDigit()
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(mine ? NorthColor.signal.opacity(0.18) : Color(.secondarySystemBackground), in: .capsule)
            .overlay { Capsule().strokeBorder(mine ? NorthColor.signal : .clear) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mine ? .isSelected : [])
    }
}

/// A person's initial in a circle.
struct CrewAvatar: View {
    let name: String

    var body: some View {
        Text(name.first.map { String($0).uppercased() } ?? "?")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(NorthColor.signal)
            .frame(width: 36, height: 36)
            .background(NorthColor.signal.opacity(0.15), in: .circle)
            .accessibilityHidden(true)
    }
}

/// Today's messages show the time; older ones the day as well.
enum CrewTime {
    static func short(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }
}
