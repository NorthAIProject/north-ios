import CoreTransferable
import NorthAPI
import NorthKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Film a set, and the coach says what it sees: each thing to fix pinned to
/// the moment in the clip, so you can check it yourself.
struct FormCheckScreen: View {
    var service: FormCheckServicing = FormCheckService()

    @State private var checks: [FormCheck] = []
    @State private var loaded = false
    @State private var picked: PhotosPickerItem?
    @State private var uploading = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                PhotosPicker(selection: $picked, matching: .videos) {
                    Label(uploading ? "Uploading…" : "Choose a Clip", systemImage: "video.badge.plus")
                }
                .disabled(uploading)
            } footer: {
                Text("Side-on, whole body in frame, one set. Up to 200 MB.")
            }
            if let error { ErrorRow(error) }
            if !checks.isEmpty {
                Section("Checks") {
                    ForEach(checks, id: \.id) { check in
                        NavigationLink {
                            FormCheckDetail(id: check.id, service: service)
                        } label: {
                            FormCheckRow(check: check)
                        }
                    }
                }
            } else if loaded {
                Section {
                    Text("No checks yet.").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Form Check")
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
        // While anything is being analysed, look again every few seconds.
        .task(id: checks.contains(where: \.inProgress)) {
            while checks.contains(where: \.inProgress), !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                await load()
            }
        }
    }

    private func load() async {
        do { checks = try await service.checks(); error = nil } catch { self.error = error.localizedDescription }
        loaded = true
    }

    private func upload(_ item: PhotosPickerItem) async {
        uploading = true
        defer {
            uploading = false
            picked = nil
        }
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else { return }
            defer { try? FileManager.default.removeItem(at: movie.url) }
            let check = try await service.upload(video: movie.url)
            checks.insert(check, at: 0)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A video from Photos, copied to a temporary file so it can be streamed up
/// rather than held in memory.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

extension FormCheck {
    var inProgress: Bool { status == .pending || status == .running }
}

private struct FormCheckRow: View {
    let check: FormCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(check.result?.exercise ?? (check.inProgress ? "Analysing…" : "Form check"))
                .font(.headline)
            HStack(spacing: 8) {
                Text(check.createdAt.formatted(.relative(presentation: .named)))
                switch check.status {
                case .pending, .running: ProgressView().controlSize(.mini)
                case .failed: Text("Could not be analysed").foregroundStyle(NorthColor.ember)
                case .done:
                    let count = check.result?.issues.count ?? 0
                    Text(count == 0 ? "Nothing to fix" : count == 1 ? "1 thing to fix" : "\(count) things to fix")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct FormCheckDetail: View {
    let id: String
    let service: FormCheckServicing

    @State private var check: FormCheck?
    @State private var error: String?

    var body: some View {
        List {
            if let check {
                if let result = check.result {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(result.exercise).font(.title2.weight(.semibold))
                            Text("CONFIDENCE: \(result.confidence.uppercased())")
                                .font(.caption.weight(.medium))
                                .tracking(1.5)
                                .foregroundStyle(.secondary)
                            Text(result.summary)
                        }
                        .padding(.vertical, 4)
                    }
                    if !result.issues.isEmpty {
                        Section("What to Fix") {
                            ForEach(Array(result.issues.enumerated()), id: \.offset) { _, issue in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(timestamp(issue.at))
                                            .font(.subheadline.monospacedDigit().weight(.medium))
                                            .foregroundStyle(NorthColor.signal)
                                        Text(issue.severity.capitalized).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(issue.observation)
                                    Text(issue.correction).font(.subheadline).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                } else if check.inProgress {
                    Section { Label("Analysing the clip…", systemImage: "hourglass") }
                } else {
                    Section { Text(check.error ?? "This clip could not be analysed.").foregroundStyle(.secondary) }
                }
            } else if let error {
                ErrorRow(error)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Form Check")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Poll until the analysis settles.
            repeat {
                do { check = try await service.check(id); error = nil } catch { self.error = error.localizedDescription; return }
                if check?.inProgress == true { try? await Task.sleep(for: .seconds(4)) }
            } while check?.inProgress == true && !Task.isCancelled
        }
    }

    private func timestamp(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}
