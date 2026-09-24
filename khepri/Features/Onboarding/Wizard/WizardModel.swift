import Foundation
import NorthAPI
import Observation

/// The first-run steps, in order.
enum WizardStep: Int, CaseIterable, Codable {
    case welcome, focusAreas, coachingStyle, firstGoal, health, notifications

    var progress: Double { Double(rawValue + 1) / Double(Self.allCases.count) }
    var next: WizardStep? { WizardStep(rawValue: rawValue + 1) }
    var previous: WizardStep? { WizardStep(rawValue: rawValue - 1) }
}

/// The life domains the server accepts, with how the wizard presents them.
enum FocusArea: String, CaseIterable, Codable, Identifiable {
    case fitness, health, work, learning, personal

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .fitness: "figure.run"
        case .health: "heart"
        case .work: "briefcase"
        case .learning: "book"
        case .personal: "person"
        }
    }

    var example: String {
        switch self {
        case .fitness: "Run a half marathon"
        case .health: "Sleep seven hours on weeknights"
        case .work: "Ship the launch without burning out"
        case .learning: "Read twelve books this year"
        case .personal: "Call my parents every Sunday"
        }
    }
}

/// The coaching presets the server knows, plus a custom description.
enum CoachingStyle: String, CaseIterable, Codable, Identifiable {
    case direct, supportive, socratic, custom

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// The server's wording for each preset, so the choice reads the same here
    /// as in the coach's instructions.
    var detail: String {
        switch self {
        case .direct: "Be direct. Skip pep talks. Challenge me."
        case .supportive: "Be warm and encouraging. Celebrate progress."
        case .socratic: "Ask questions. Help me think it through."
        case .custom: "Describe it in your own words."
        }
    }
}

/// What the person has answered so far. Saved after every change, so quitting
/// halfway resumes at the same step with the same answers.
struct WizardDraft: Codable, Equatable {
    var step: WizardStep = .welcome
    var focusAreas: [FocusArea] = []
    var coachingStyle: CoachingStyle?
    var customStyle = ""
    var goal = ""
    /// The server accepted the answers; only permission steps remain.
    var submitted = false
}

/// Drives the first-run wizard: the current step, the answers, validation,
/// sending the answers, and resuming after a quit.
@MainActor
@Observable
final class WizardModel {
    private(set) var draft: WizardDraft {
        didSet { save() }
    }
    private(set) var isSubmitting = false
    /// Server or validation messages keyed by the field they belong to.
    private(set) var fieldErrors: [String: String] = [:]
    private(set) var submitError: String?

    let user: APIUser
    private let auth: AuthServicing
    private let defaults: UserDefaults
    private var storageKey: String { "wizard.draft.\(user.id)" }

    init(user: APIUser, auth: AuthServicing = AuthService.shared, defaults: UserDefaults = .standard) {
        self.user = user
        self.auth = auth
        self.defaults = defaults
        let key = "wizard.draft.\(user.id)"
        if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(WizardDraft.self, from: data) {
            draft = saved
        } else {
            draft = WizardDraft()
        }
    }

    var step: WizardStep { draft.step }

    // MARK: Answers

    func toggle(_ area: FocusArea) {
        if let index = draft.focusAreas.firstIndex(of: area) {
            draft.focusAreas.remove(at: index)
        } else {
            draft.focusAreas.append(area)
        }
        fieldErrors["focus_areas"] = nil
    }

    func choose(_ style: CoachingStyle) {
        draft.coachingStyle = style
        fieldErrors["coaching_style"] = nil
    }

    func setCustomStyle(_ text: String) {
        draft.customStyle = text
        fieldErrors["coaching_style"] = nil
    }

    func setGoal(_ text: String) {
        draft.goal = text
        fieldErrors["goal_title"] = nil
    }

    /// Whether the current step has what it needs to move on. Mirrors the
    /// server's rules so the button is honest; the server still decides.
    var canContinue: Bool {
        switch draft.step {
        case .welcome, .health, .notifications:
            true
        case .focusAreas:
            !draft.focusAreas.isEmpty
        case .coachingStyle:
            switch draft.coachingStyle {
            case nil: false
            case .custom?: draft.customStyle.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
            case _?: true
            }
        case .firstGoal:
            !draft.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: Navigation

    /// Moves to the next step. Leaving the goal step sends the answers; the
    /// wizard only moves on if the server accepts them.
    /// - Returns: the onboarded user once the last step is done, else nil.
    func advance() async -> APIUser? {
        guard canContinue else { return nil }
        if draft.step == .firstGoal, !draft.submitted {
            guard await submit() else { return nil }
        }
        if let next = draft.step.next {
            draft.step = next
            return nil
        }
        return finish()
    }

    func goBack() {
        // Once the server has the answers, going back would suggest they can
        // still be changed here; Settings is where they change later.
        guard let previous = draft.step.previous, !(draft.submitted && previous == .firstGoal) else { return }
        draft.step = previous
    }

    var canGoBack: Bool {
        guard let previous = draft.step.previous else { return false }
        return !(draft.submitted && previous == .firstGoal)
    }

    // MARK: Server

    private var submittedUser: APIUser?

    private func submit() async -> Bool {
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        let answers = OnboardingAnswers(
            focusAreas: draft.focusAreas.map(\.rawValue),
            coachingStyle: draft.coachingStyle?.rawValue ?? CoachingStyle.custom.rawValue,
            coachingStyleCustom: draft.coachingStyle == .custom ? draft.customStyle : nil,
            nearTermGoal: draft.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            submittedUser = try await auth.completeOnboarding(answers)
            draft.submitted = true
            return true
        } catch let APIError.fieldValidation(message, fields) {
            fieldErrors = fields
            submitError = fields.isEmpty ? message : nil
            if let step = Self.step(forField: fields.keys.first) { draft.step = step }
            return false
        } catch {
            submitError = error.localizedDescription
            return false
        }
    }

    /// Where a server field error belongs.
    static func step(forField field: String?) -> WizardStep? {
        switch field {
        case "focus_areas": .focusAreas
        case "coaching_style": .coachingStyle
        case "goal_title": .firstGoal
        default: nil
        }
    }

    private func finish() -> APIUser {
        defaults.removeObject(forKey: storageKey)
        var user = submittedUser ?? user
        user.needsOnboarding = false
        return user
    }

    private func save() {
        if let data = try? JSONEncoder().encode(draft) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
