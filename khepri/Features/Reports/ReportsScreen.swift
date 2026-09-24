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

private struct ReportRow: View {
    let report: ReportSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(report.kind == .weekly ? "WEEKLY" : "BRIEFING")
                    .font(.caption2.weight(.medium))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                if report.archived {
                    Image(systemName: "archivebox").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(report.title).font(.headline)
            Text(status)
                .font(.caption)
                .foregroundStyle(report.status == .failed ? NorthColor.ember : .secondary)
        }
        .padding(.vertical, 2)
    }

    private var status: String {
        switch report.status {
        case .pending: "Being written…"
        case .failed: "Could not be written"
        case .ready: report.generatedAt.map { $0.formatted(.relative(presentation: .named)) } ?? ""
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
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.value1.title).font(.title2.weight(.semibold))
                        Text(period(report.value1))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    MarkdownBlocksView(markdown: report.value2.body)
                    Divider()
                    HStack(spacing: 16) {
                        Text("Was this useful?").foregroundStyle(.secondary)
                        Spacer()
                        rateButton(true, report.value1.helpful)
                        rateButton(false, report.value1.helpful)
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

    private func rateButton(_ value: Bool, _ current: Bool?) -> some View {
        let selected = current == value
        return Button {
            Task {
                // Tapping the chosen answer again clears it.
                do { report = try await service.rate(id, helpful: selected ? nil : value) } catch { self.error = error.localizedDescription }
            }
        } label: {
            Image(systemName: (value ? "hand.thumbsup" : "hand.thumbsdown") + (selected ? ".fill" : ""))
        }
        .accessibilityLabel(value ? "Useful" : "Not useful")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func period(_ report: ReportSummary) -> String {
        guard let start = CalendarDay.date(from: report.periodStart), let end = CalendarDay.date(from: report.periodEnd) else { return "" }
        if report.periodStart == report.periodEnd { return start.formatted(date: .complete, time: .omitted) }
        return (start..<end.addingTimeInterval(1)).formatted(.interval.day().month())
    }
}
