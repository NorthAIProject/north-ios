import AVKit
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
    var uploader: FormCheckUploader = .shared

    @State private var checks: [FormCheck] = []
    @State private var loaded = false
    @State private var picked: PhotosPickerItem?
    /// Writing the picked clip into an upload; the upload itself is listed.
    @State private var preparing = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                PhotosPicker(selection: $picked, matching: .videos) {
                    Label(preparing ? String(localized: "Preparing…") : String(localized: "Choose a Clip"), systemImage: "video.badge.plus")
                }
                .disabled(preparing)
            } footer: {
                Text("Side-on, whole body in frame, one set. Big clips are made smaller to send.")
            }
            if let error { ErrorRow(error) }
            if !uploader.uploads.isEmpty {
                Section {
                    ForEach(uploader.uploads) { upload in
                        FormCheckUploadRow(
                            upload: upload,
                            retry: { Task { await uploader.retry(upload.id) } },
                            dismiss: { uploader.dismiss(upload.id) }
                        )
                    }
                }
            }
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
        // The server took a clip: its check is now in the list, analysing.
        .onChange(of: uploader.acceptedCount) {
            Task { await load() }
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

    /// Hands the clip to the background uploader, which copies it into a
    /// body of its own, so the picked copy can go straight away.
    private func upload(_ item: PhotosPickerItem) async {
        preparing = true
        defer {
            preparing = false
            picked = nil
        }
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else { return }
            defer { try? FileManager.default.removeItem(at: movie.url) }
            let video = try await FormCheckVideo.fitting(movie.url)
            defer { if video != movie.url { try? FileManager.default.removeItem(at: video) } }
            try await uploader.upload(video: video)
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

/// A clip on its way up, or one that did not make it.
private struct FormCheckUploadRow: View {
    let upload: FormCheckUpload
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        if let failure = upload.failure {
            VStack(alignment: .leading, spacing: 8) {
                ErrorRow(failure)
                HStack {
                    Button("Try Again", action: retry)
                    Spacer()
                    Button("Dismiss", role: .destructive, action: dismiss)
                }
                .buttonStyle(.borderless)
            }
        } else {
            Label {
                Text("Uploading… you can leave the app")
            } icon: {
                ProgressView()
            }
        }
    }
}

private struct FormCheckRow: View {
    let check: FormCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(check.result?.exercise ?? (check.inProgress ? String(localized: "Analysing…") : String(localized: "Form check")))
                .font(.headline)
            HStack(spacing: 8) {
                Text(check.createdAt.formatted(.relative(presentation: .named)))
                switch check.status {
                case .pending, .running: ProgressView().controlSize(.mini)
                case .failed: Text("Could not be analysed").foregroundStyle(NorthColor.ember)
                case .done:
                    let count = check.result?.issues.count ?? 0
                    Text(count == 0 ? String(localized: "Nothing to fix")
                         : count == 1 ? String(localized: "1 thing to fix")
                         : String(localized: "\(count) things to fix"))
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
    /// Made once from the first signed link. Every poll returns a fresh link,
    /// and swapping the player for each would restart the clip.
    @State private var player: AVPlayer?
    /// The issue being looked at: its marker and its row are the gold ones.
    @State private var selected: Int?

    var body: some View {
        List {
            if let player {
                Section {
                    VideoPlayer(player: player)
                        .aspectRatio(9 / 16, contentMode: .fit)
                        .frame(maxHeight: 420)
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                    if let issues = check?.result?.issues, !issues.isEmpty, let duration = check?.durationSeconds, duration > 0 {
                        FormCheckTimeline(
                            issues: issues.map { FormCheckMark(at: $0.at, severity: $0.severity) },
                            durationSeconds: duration,
                            selected: selected
                        ) { select($0) }
                    }
                }
            }
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
                    } footer: {
                        if check.method == "stills", let count = check.frames?.count, count > 0 {
                            Text("Khepri looked at \(count) stills from your clip. It judges positions, not speed.")
                        }
                    }
                    if !result.issues.isEmpty {
                        Section("What to Fix") {
                            ForEach(Array(result.issues.enumerated()), id: \.offset) { index, issue in
                                Button {
                                    select(index)
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Label(timestamp(issue.at), systemImage: player == nil ? "clock" : "pause.fill")
                                                    .font(.subheadline.monospacedDigit().weight(.medium))
                                                    .foregroundStyle(selected == index ? NorthColor.signal : .primary)
                                                Text(issue.severity.capitalized).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Text(issue.observation)
                                            Text(issue.correction).font(.subheadline).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        if let link = issue.frameUrl, let url = URL(string: link) {
                                            AsyncImage(url: url) { image in
                                                image.resizable().scaledToFit()
                                            } placeholder: {
                                                Color.clear
                                            }
                                            .frame(width: 64, height: 96)
                                            .clipShape(.rect(cornerRadius: NorthRadius.small, style: .continuous))
                                            .accessibilityHidden(true)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)
                                .disabled(player == nil)
                                .accessibilityHint(player == nil ? "" : String(localized: "Shows this moment in the clip"))
                            }
                        }
                    }
                } else if check.inProgress {
                    Section { Label("Analysing the clip…", systemImage: "hourglass") }
                } else {
                    Section { Text(check.error ?? String(localized: "This clip could not be analysed.")).foregroundStyle(.secondary) }
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
                if player == nil, let link = check?.playbackUrl, let url = URL(string: link) {
                    player = AVPlayer(url: url)
                }
                if check?.inProgress == true { try? await Task.sleep(for: .seconds(4)) }
            } while check?.inProgress == true && !Task.isCancelled
        }
    }

    /// Stops on the moment itself. The still the coach named is one frame,
    /// so the seek is exact: the default tolerance lands on a keyframe that
    /// can be seconds away.
    private func select(_ index: Int) {
        guard let player, let issue = check?.result?.issues[safe: index] else { return }
        selected = index
        player.pause()
        player.seek(
            to: CMTime(seconds: issue.at, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func timestamp(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}

/// The clip as a line, with a marker where each issue is visible.
///
/// A marker's shape says how serious it is, so colour is never the only
/// signal: a diamond to fix before adding load, a filled dot worth fixing, a
/// ring for a minor one. VoiceOver reads the issue rows below instead.
struct FormCheckTimeline: View {
    let issues: [FormCheckMark]
    let durationSeconds: Double
    let selected: Int?
    let select: (Int) -> Void

    private static let hit: CGFloat = 44

    var body: some View {
        GeometryReader { proxy in
            let track = max(proxy.size.width - Self.hit, 0)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(NorthColor.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, Self.hit / 2)
                ForEach(Array(issues.enumerated()), id: \.offset) { index, issue in
                    Button {
                        select(index)
                    } label: {
                        FormCheckMarker(severity: issue.severity, isSelected: selected == index)
                            .frame(width: Self.hit, height: Self.hit)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .offset(x: track * FormCheckTimeline.position(of: issue.at, in: durationSeconds))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: Self.hit)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityHidden(true)
    }

    /// Where a moment sits along the line, 0 to 1. Clamped, so a wrong
    /// length cannot push a marker off it.
    static func position(of seconds: Double, in durationSeconds: Double) -> Double {
        guard durationSeconds > 0, seconds.isFinite else { return 0 }
        return min(max(seconds / durationSeconds, 0), 1)
    }
}

/// One issue as the timeline draws it.
struct FormCheckMark: Equatable {
    let at: Double
    let severity: String
}

private struct FormCheckMarker: View {
    let severity: String
    let isSelected: Bool

    var body: some View {
        let color: Color = isSelected ? NorthColor.signal : .primary
        Group {
            switch severity {
            case "critical":
                Rectangle().fill(color).frame(width: 11, height: 11).rotationEffect(.degrees(45))
            case "moderate":
                Circle().fill(color).frame(width: 12, height: 12)
            default:
                Circle().strokeBorder(color, lineWidth: 2).frame(width: 11, height: 11)
            }
        }
        .scaleEffect(isSelected ? 1.25 : 1)
        .animation(.snappy, value: isSelected)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
