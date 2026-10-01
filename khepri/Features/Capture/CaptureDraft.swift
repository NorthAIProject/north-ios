import Foundation
import NorthAPI
import Observation

/// One sentence on its way to being logged: the text, the model's reading of
/// it, and which of the read items the person kept.
///
/// Items the server flagged with a `problem` can never be chosen, so a
/// reading the server already refused is not sent back to it. Everything
/// else starts chosen, because the common case is that the model got it
/// right and the person only unticks the odd mistake.
@MainActor @Observable
final class CaptureDraft {
    var text = ""
    private(set) var items: [CaptureItem] = []
    private(set) var unparsed: [String] = []
    /// Indices into `items`. Indices rather than the items themselves,
    /// because two identical readings ("250 ml", "250 ml") are two drinks.
    private(set) var chosen: Set<Int> = []
    private(set) var isBusy = false
    private(set) var error: String?
    /// A short line after a write, e.g. "Logged 3".
    private(set) var result: String?

    private let service: CaptureServicing

    /// nil means the live service. Made here rather than as a default
    /// argument, which would be built outside the main actor.
    init(service: CaptureServicing? = nil) {
        self.service = service ?? CaptureService()
    }

    var canReview: Bool { !isBusy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasReading: Bool { !items.isEmpty || !unparsed.isEmpty }

    func isWritable(_ index: Int) -> Bool { items.indices.contains(index) && items[index].problem == nil }
    func isChosen(_ index: Int) -> Bool { chosen.contains(index) }

    /// Ticks or unticks one item. Items with a problem stay unticked.
    func setChosen(_ index: Int, _ on: Bool) {
        guard isWritable(index) else { return }
        if on { chosen.insert(index) } else { chosen.remove(index) }
    }

    /// What "Log" would send, in the order the model read them.
    var itemsToLog: [CaptureItem] {
        items.indices.filter { chosen.contains($0) && isWritable($0) }.map { items[$0] }
    }

    var canLog: Bool { !isBusy && !itemsToLog.isEmpty }

    /// Asks the server to read the text. Nothing is written yet.
    func review() async {
        guard canReview else { return }
        isBusy = true
        defer { isBusy = false }
        result = nil
        do {
            let reading = try await service.parse(text.trimmingCharacters(in: .whitespacesAndNewlines))
            items = reading.items
            unparsed = reading.unparsed
            chosen = Set(items.indices.filter(isWritable))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Writes the chosen items. Returns true when anything was saved, so the
    /// screen knows to reload; the draft is cleared for the next sentence.
    @discardableResult
    func log() async -> Bool {
        guard canLog else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            let outcome = try await service.commit(itemsToLog)
            result = Self.summary(outcome)
            error = nil
            reset()
            return outcome.written > 0
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Drops the reading and starts over, keeping the last result line.
    func reset() {
        text = ""
        items = []
        unparsed = []
        chosen = []
    }

    static func summary(_ outcome: CaptureOutcome) -> String {
        let logged = String(localized: "Logged \(outcome.written)")
        guard outcome.failed > 0 else { return logged }
        return logged + String(localized: ", \(outcome.failed) could not be saved")
    }
}
