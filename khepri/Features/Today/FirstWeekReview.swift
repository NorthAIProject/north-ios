import NorthAPI
import NorthKit
import SwiftUI

typealias FirstWeekReview = Components.Schemas.FirstWeekReview

/// The day-7 review. Opening it closes the week, as on the web, so the
/// store finishes once and shows the review the answer carries.
@MainActor
@Observable
final class FirstWeekReviewStore {
    private(set) var week: FirstWeek?
    private(set) var error: String?
    private var opened = false
    private let service: FirstWeekServicing

    init(service: FirstWeekServicing = FirstWeekService()) {
        self.service = service
    }

    var review: FirstWeekReview? { week?.review }

    func open() async {
        guard !opened else { return }
        opened = true
        do {
            week = try await service.finish()
        } catch {
            // A 409 means the week is already closed (opened on another
            // device) or not at day 7 yet: show whatever review there is.
            if let current = try? await service.current(), current.review != nil {
                week = current
            } else {
                self.error = error.localizedDescription
            }
        }
    }
}

/// The week looked back on, then the rest of Khepri: "What next?".
struct FirstWeekReviewFlow: View {
    @State private var store = FirstWeekReviewStore()
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "Your first week", comment: "Title of the first-week review"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
                .task { await store.open() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let week = store.week, let review = week.review {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    reviewCard(review, total: week.totalDays)
                    whatNext
                }
                .padding(16)
            }
        } else if let error = store.error {
            ContentUnavailableView("Could Not Load", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
            ProgressView()
        }
    }

    private func reviewCard(_ review: FirstWeekReview, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NorthCardHeader(String(localized: "\(review.daysDone) of \(total) days done", comment: "First-week progress, read by VoiceOver"))
            Text(review.text)
                .font(.body)
                .accessibilityIdentifier("first-week-review-text")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .northSurfaceCard(padding: 16)
    }

    private var whatNext: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What next?", comment: "Heading above the links out of the first-week review")
                .font(.headline)
            Text("The rest of Khepri is open now. Pick one thing to keep going with.", comment: "First-week review, intro to the next steps")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            next(String(localized: "Build a habit", comment: "First-week review link to Care"), systemImage: "leaf", to: .section("care"))
            next(String(localized: "Pick a training plan", comment: "First-week review link to Training"), systemImage: "figure.strengthtraining.traditional", to: .tab(.training))
            next(String(localized: "Join a crew", comment: "First-week review link to Crews"), systemImage: "person.3", to: .section("crews"))
        }
    }

    private func next(_ title: String, systemImage: String, to destination: AppDestination) -> some View {
        Button {
            dismiss()
            router.open(destination)
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }
}
