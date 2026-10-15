import NorthAPI
import NorthKit
import SwiftUI

/// The last 7 or 30 days: totals against the period before, which days had
/// training, food and a check-in, the period's highlights, and a button to
/// share it out or post it to friends.
struct RecapScreen: View {
    let store: RecapStore
    @State var range: RecapRange = .week
    @State private var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    private var recap: Recap? { store.recaps[range] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Period", selection: $range) {
                        ForEach(RecapRange.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let recap {
                        Label {
                            Text("\(recap.period) · Private to you")
                        } icon: {
                            Image(systemName: "lock")
                        }
                        .font(.north(.subheadline))
                        .foregroundStyle(.secondary)

                        Tiles(recap: recap)
                        DailyCard(recap: recap, range: range)
                        if !recap.highlights.isEmpty {
                            Highlights(recap: recap)
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
            .navigationTitle(range.heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let recap {
                    ShareBar(recap: recap, range: range, image: image, store: store)
                }
            }
        }
        .task(id: range) {
            store.resetPost()
            await store.load(range)
        }
        .onChange(of: recap, initial: true) { _, latest in
            image = latest.flatMap { RecapShareCard.render($0, range: range) }
        }
    }
}

/// Six numbers, five with the change against the period before.
private struct Tiles: View {
    let recap: Recap

    var body: some View {
        let now = recap.totals, before = recap.prior
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 18) {
            GridRow {
                Tile(label: String(localized: "Active days"), value: now.activeDays, prior: before.activeDays)
                Tile(label: String(localized: "Workouts"), value: now.workouts, prior: before.workouts)
            }
            GridRow {
                Tile(label: String(localized: "Sets"), value: now.sets, prior: before.sets)
                Tile(label: String(localized: "Foods logged"), value: now.foodLogs, prior: before.foodLogs)
            }
            GridRow {
                Tile(label: String(localized: "Check-ins"), value: now.checkIns, prior: before.checkIns)
                Tile(label: String(localized: "Check-in streak"), value: recap.checkInStreak, prior: nil)
            }
        }
        .northSurfaceCard(padding: 16)
    }
}

private struct Tile: View {
    let label: String
    let value: Int
    let prior: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value, format: .number).northDisplayNumber(.title)
                if let prior, value != prior {
                    let delta = value - prior
                    Label {
                        Text(delta, format: .number.sign(strategy: .always()))
                    } icon: {
                        Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                    }
                    .labelStyle(.titleAndIcon)
                    .font(.north(.caption).weight(.medium))
                    .foregroundStyle(delta > 0 ? AnyShapeStyle(NorthColor.signal) : AnyShapeStyle(.secondary))
                    .accessibilityLabel(String(localized: "\(delta, format: .number.sign(strategy: .always())) on the period before"))
                }
            }
            Text(label).font(.north(.subheadline)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct DailyCard: View {
    let recap: Recap
    let range: RecapRange

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NorthCardHeader(String(localized: "Daily activity"))
            RecapBars(days: recap.days, height: 140)
            RecapLegend()
        }
        .northSurfaceCard(padding: 16)
    }
}

private struct Highlights: View {
    let recap: Recap

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NorthCardHeader(String(localized: "Highlights"))
            ForEach(Array(recap.highlights.enumerated()), id: \.offset) { index, item in
                if index > 0 { Divider() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.north(.body))
                    Text(item.occurredAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.north(.footnote))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .northSurfaceCard(padding: 16)
    }
}

/// "Share recap": out through the share sheet as an image and a line of
/// text, or to the friends feed. A post friends cannot see says so and
/// offers to share training, which is what recaps show with.
private struct ShareBar: View {
    let recap: Recap
    let range: RecapRange
    let image: UIImage?
    let store: RecapStore
    @State private var askingToShareTraining = false

    var body: some View {
        VStack(spacing: 8) {
            if let note {
                Text(note)
                    .font(.north(.footnote))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Menu {
                if let image {
                    let picture = Image(uiImage: image)
                    ShareLink(item: picture, message: Text(recap.shareText(range)),
                              preview: SharePreview(range.heading, image: picture)) {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                } else {
                    ShareLink(item: recap.shareText(range)) {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    Task { await store.share(range) }
                } label: {
                    Label("Post to friends", systemImage: "person.2")
                }
            } label: {
                // Drawn here rather than with northProminentButton(): a Menu
                // ignores button styles, and this is the screen's one action.
                Label("Share recap", systemImage: "square.and.arrow.up")
                    .font(.north(.headline))
                    .foregroundStyle(NorthColor.primaryForeground)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(NorthColor.primary, in: .capsule)
                    .opacity(store.post == .posting ? 0.5 : 1)
            }
            .disabled(store.post == .posting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .onChange(of: store.post) { _, post in
            if post == .hidden { askingToShareTraining = true }
        }
        .alert("Friends can't see it yet", isPresented: $askingToShareTraining) {
            Button("Share training and post") {
                Task { await store.share(range, shareTraining: true) }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Recaps show with your training, and you're not sharing training with friends.")
        }
    }

    private var note: String? {
        switch store.post {
        case .posted: String(localized: "Posted to your friends feed.")
        case .hidden: String(localized: "Posted, but only you can see it.")
        case .failed(let message): message
        case .idle, .posting: nil
        }
    }
}
