import NorthAPI
import NorthKit
import SwiftUI

typealias BellNudge = Components.Schemas.BellNudge

protocol NudgesServicing: Sendable {
    func nudges() async throws -> Components.Schemas.NudgeList
    func open(_ id: String) async throws -> BellNudge
    func dismiss(_ id: String) async throws
}

struct NudgesService: NudgesServicing {
    var api: Client = API.shared

    func nudges() async throws -> Components.Schemas.NudgeList { try await NorthAPI.call { try await api.listNudges().ok.body.json } }
    func open(_ id: String) async throws -> BellNudge { try await NorthAPI.call { try await api.openNudge(path: .init(nudgeID: id)).ok.body.json } }
    func dismiss(_ id: String) async throws { try await NorthAPI.call { _ = try await api.dismissNudge(path: .init(nudgeID: id)).ok } }
}

/// The bell: the coach's notes that something needs you, same as the web's.
/// Opening one goes where it points, through the app's router.
struct NudgesBellButton: View {
    var service: NudgesServicing = NudgesService()
    @State private var unread = 0
    @State private var showing = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: unread > 0 ? "bell.badge" : "bell")
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityLabel(unread > 0 ? "Notifications, \(unread) unread" : "Notifications")
        .sheet(isPresented: $showing, onDismiss: { Task { await refresh() } }) {
            NudgesList(service: service)
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
    }

    private func refresh() async {
        unread = (try? await service.nudges().unread) ?? unread
    }
}

private struct NudgesList: View {
    let service: NudgesServicing
    @State private var nudges: [BellNudge] = []
    @State private var loaded = false
    @State private var error: String?
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let error { ErrorRow(error) }
                if loaded, nudges.isEmpty {
                    Text("Nothing needs you right now.").foregroundStyle(.secondary)
                }
                ForEach(nudges, id: \.id) { nudge in
                    Button {
                        Task { await open(nudge) }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Circle().fill(nudge.unread ? NorthColor.signal : .clear).frame(width: 8, height: 8).padding(.top, 6)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(nudge.title).font(.headline).foregroundStyle(.primary)
                                Text(nudge.body).font(.subheadline).foregroundStyle(.secondary)
                                Text(nudge.createdAt.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .swipeActions {
                        Button("Dismiss") {
                            Task {
                                do { try await service.dismiss(nudge.id); await load() } catch { self.error = error.localizedDescription }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
        }
    }

    private func load() async {
        do { nudges = try await service.nudges().nudges; error = nil } catch { self.error = error.localizedDescription }
        loaded = true
    }

    private func open(_ nudge: BellNudge) async {
        do {
            let opened = try await service.open(nudge.id)
            dismiss()
            if let url = URL(string: opened.href) { router.open(url: url) }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
