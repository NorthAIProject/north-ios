import NorthAPI
import NorthKit
import SwiftUI

typealias ReportSummary = Components.Schemas.ReportSummary
typealias ReportDetail = Components.Schemas.ReportDetail

protocol ReportsServicing: Sendable {
    func reports(archived: Bool) async throws -> [ReportSummary]
    func report(_ id: String) async throws -> ReportDetail
    func rate(_ id: String, helpful: Bool?) async throws -> ReportDetail
    func archive(_ id: String) async throws
}

struct ReportsService: ReportsServicing {
    var api: Client = API.shared

    func reports(archived: Bool) async throws -> [ReportSummary] {
        try await NorthAPI.call { try await api.listReports(query: .init(archived: archived)).ok.body.json.reports }
    }

    func report(_ id: String) async throws -> ReportDetail {
        try await NorthAPI.call { try await api.getReport(path: .init(reportID: id)).ok.body.json }
    }

    func rate(_ id: String, helpful: Bool?) async throws -> ReportDetail {
        try await NorthAPI.call { try await api.rateReport(path: .init(reportID: id), body: .json(.init(helpful: helpful))).ok.body.json }
    }

    func archive(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.archiveReport(path: .init(reportID: id)).noContent }
    }
}

/// The coach's written reviews: a report each week and a briefing each
/// morning, newest first.
struct ReportsScreen: View {
    var service: ReportsServicing = ReportsService()
    @State private var reports: [ReportSummary] = []
    @State private var showArchived = false
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        Group {
            if !loaded, error == nil {
                ProgressView()
            } else if reports.isEmpty, error == nil {
                ContentUnavailableView("No reports yet", systemImage: "doc.text",
                                       description: Text("Your coach writes one at the end of each week, from your check-ins, training and goals."))
            } else {
                List {
                    if let error { ErrorRow(error) }
                    ForEach(reports, id: \.id) { report in
                        NavigationLink {
                            ReportDetailView(id: report.id, service: service) { Task { await load() } }
                        } label: {
                            ReportRow(report: report)
                        }
                        .disabled(report.status == .pending)
                    }
                }
            }
        }
        .navigationTitle("Reports")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle("Show Archived", systemImage: "archivebox", isOn: $showArchived)
                    .toggleStyle(.button)
            }
        }
        .task(id: showArchived) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            reports = try await service.reports(archived: showArchived)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }
}

private extension ReportSummary {
    var kindLabel: String { kind == .weekly ? String(localized: "Weekly report") : String(localized: "Morning briefing") }
    var kindSymbol: String { kind == .weekly ? "calendar" : "sun.horizon" }
}

private struct ReportRow: View {
    let report: ReportSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: report.kindSymbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(NorthColor.agent)
                .frame(width: 36, height: 36)
                .background(NorthColor.agent.opacity(0.12), in: .rect(cornerRadius: NorthRadius.medium, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(report.kindLabel).northEyebrow()
                    if report.archived {
                        Image(systemName: "archivebox").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(report.title)
                    .font(.north(.headline))
                    .lineLimit(2)
                status
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var status: some View {
        switch report.status {
        case .pending:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Being written…")
            }
            .font(.north(.caption))
            .foregroundStyle(.secondary)
        case .failed:
            Text("Could not be written")
                .font(.north(.caption))
                .foregroundStyle(NorthColor.ember)
        case .ready:
            Text(report.generatedAt.map { $0.formatted(.relative(presentation: .named)) } ?? "")
                .font(.north(.caption))
                .foregroundStyle(.secondary)
        }
    }
}

/// One report, to read, rate and put away.
struct ReportDetailView: View {
    let id: String
    let service: ReportsServicing
    let onChange: () -> Void

    @State private var report: ReportDetail?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            if let report {
                VStack(alignment: .leading, spacing: 20) {
                    ReportHeader(summary: report.value1, period: period(report.value1))
                    ReportBody(document: MarkdownDocument(markdown: report.value2.body))
                    ReportRating(helpful: report.value1.helpful) { helpful in
                        Task {
                            do { self.report = try await service.rate(id, helpful: helpful) } catch { self.error = error.localizedDescription }
                        }
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                }
                .padding(20)
            } else if let error {
                ContentUnavailableView("This report did not load", systemImage: "wifi.exclamationmark", description: Text(error))
            } else {
                ProgressView().padding(.top, 48)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if report?.value1.archived == false {
                ToolbarItem(placement: .primaryAction) {
                    Button("Archive", systemImage: "archivebox") {
                        Task {
                            do { try await service.archive(id); onChange(); dismiss() } catch { self.error = error.localizedDescription }
                        }
                    }
                }
            }
        }
        .task {
            do { report = try await service.report(id) } catch { self.error = error.localizedDescription }
        }
    }

    private func period(_ report: ReportSummary) -> String {
        guard let start = CalendarDay.date(from: report.periodStart), let end = CalendarDay.date(from: report.periodEnd) else { return "" }
        if report.periodStart == report.periodEnd { return start.formatted(date: .complete, time: .omitted) }
        return (start..<end.addingTimeInterval(1)).formatted(.interval.day().month())
    }
}

private struct ReportHeader: View {
    let summary: ReportSummary
    let period: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary.kindLabel).northEyebrow(NorthColor.agent)
            Text(summary.title)
                .font(.north(.title).weight(.bold))
                .accessibilityAddTraits(.isHeader)
            if !period.isEmpty {
                Text(period)
                    .font(.north(.subheadline))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The opening as the coach's voice, set apart by a bar in the agent colour,
/// then each section on its own card. A briefing has no headings, so it is
/// all opening.
private struct ReportBody: View {
    let document: MarkdownDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !document.lead.isEmpty {
                ReportLead(blocks: document.lead)
            }
            ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 12) {
                    if let heading = section.heading {
                        NorthCardHeader(heading)
                            .accessibilityAddTraits(.isHeader)
                    }
                    MarkdownBlocksView(blocks: section.blocks)
                }
                .northSurfaceCard()
            }
        }
    }
}

private struct ReportLead: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                if case .paragraph(let text) = block {
                    Text(Markdown.render(text))
                        .font(.north(.title3).weight(.light))
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    MarkdownBlocksView(blocks: [block])
                }
            }
        }
        .padding(.leading, 16)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(NorthColor.agent)
                .frame(width: 3)
        }
    }
}

private struct ReportRating: View {
    let helpful: Bool?
    let onRate: (Bool?) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("Was this useful?")
                .font(.north(.subheadline))
                .foregroundStyle(.secondary)
            Spacer()
            button(true)
            button(false)
        }
        .northCard()
        .sensoryFeedback(.selection, trigger: helpful)
    }

    private func button(_ value: Bool) -> some View {
        let selected = helpful == value
        return Button {
            // Tapping the chosen answer again clears it.
            onRate(selected ? nil : value)
        } label: {
            Image(systemName: (value ? "hand.thumbsup" : "hand.thumbsdown") + (selected ? ".fill" : ""))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(selected ? NorthColor.signal : .secondary)
        .accessibilityLabel(value ? Text("Useful") : Text("Not useful"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#if DEBUG
private struct PreviewReports: ReportsServicing {
    static let weekly = ReportDetail(
        value1: .init(id: "w", kind: .weekly, title: "A steady week, short on sleep", periodStart: "2026-10-05",
                      periodEnd: "2026-10-11", status: .ready, generatedAt: .now, archived: false, helpful: true),
        value2: .init(body: """
        # A steady week, short on sleep

        Ana, you trained four times and checked in five days out of seven.
        Sleep averaged **6.4 h**, the lowest in a month.

        ## What moved

        - Squat top set went from 80 to **85 kg**.
        - You wrote "finally felt strong on the Thursday run".

        ## What stalled

        Wednesday and Friday check-ins both said energy 2/5, each after a night under six hours.

        ## Next week

        1. Keep Monday's lower-body session as planned.
        2. Lights out by 23:00 on the three nights before training.
        """))

    static let briefing = ReportDetail(
        value1: .init(id: "b", kind: .daily, title: "Bom dia, Ana", periodStart: "2026-10-14",
                      periodEnd: "2026-10-14", status: .ready, generatedAt: .now, archived: false, helpful: nil),
        value2: .init(body: """
        Hoje a recuperação está **baixa** e tens treino de pernas marcado.
        Se quiseres, usa "Take it lighter" no cartão de treino.

        O último check-in foi ontem à noite: energia 3/5.
        """))

    func reports(archived: Bool) async throws -> [ReportSummary] {
        [Self.briefing.value1, Self.weekly.value1,
         .init(id: "p", kind: .weekly, title: "This week", periodStart: "2026-10-12", periodEnd: "2026-10-18",
               status: .pending, archived: false)]
    }

    func report(_ id: String) async throws -> ReportDetail { id == "b" ? Self.briefing : Self.weekly }
    func rate(_ id: String, helpful: Bool?) async throws -> ReportDetail { try await report(id) }
    func archive(_ id: String) async throws {}
}

#Preview("Reports") {
    NavigationStack { ReportsScreen(service: PreviewReports()) }
}

#Preview("Weekly") {
    NavigationStack { ReportDetailView(id: "w", service: PreviewReports()) {} }
}

#Preview("Briefing") {
    NavigationStack { ReportDetailView(id: "b", service: PreviewReports()) {} }
}
#endif
