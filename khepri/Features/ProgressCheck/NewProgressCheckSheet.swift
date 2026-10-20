import NorthAPI
import NorthKit
import PhotosUI
import SwiftUI
import UIKit

/// A new progress check: a photo per pose beside the last one, then the date
/// and the numbers. Photos and numbers save together, and either alone is a
/// check.
struct NewProgressCheckSheet: View {
    let store: ProgressCheckStore
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    @State private var photos: ProgressPhotos = [:]
    @State private var draft = ProgressCheckDraft()
    @State private var saving = false
    @State private var error: String?
    @State private var estimating = false
    @State private var estimate: ProgressCheckDraft.EstimateOutcome?
    @State private var estimateError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ProgressPose.allCases) { pose in
                        ProgressPoseSlot(
                            pose: pose, last: store.list?.lastPhotos[pose], photo: $photos[pose]
                        ) { message in
                            error = message
                        }
                    }
                } header: {
                    Text("Photos")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Front and side photos make a complete check; back is optional. Every number is optional too.")
                        Label("Your photos are private. Only you can see them.", systemImage: "lock")
                    }
                }
                if let assist = store.assist, assist.available, let provider = assist.providerLabel {
                    estimateSection(provider: provider, own: assist.ownProvider)
                }
                measurementsSection
                if let error {
                    ErrorRow(error)
                }
            }
            .navigationTitle("New check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save check") { Task { await save() } }
                        .disabled(!canSave)
                        .accessibilityIdentifier("progress-save")
                }
            }
            .interactiveDismissDisabled(saving || !photos.isEmpty || draft.hasMeasurement)
        }
    }

    private var canSave: Bool {
        !saving && !estimating && draft.invalidFields.isEmpty && (!photos.isEmpty || draft.hasMeasurement)
    }

    /// The provider is named before anything is sent.
    private func estimateSection(provider: String, own: Bool) -> some View {
        Section {
            Button {
                Task { await runEstimate() }
            } label: {
                Label(estimating ? "Estimating…" : "Estimate from photos", systemImage: "sparkles")
            }
            .disabled(estimating || saving || (photos[.front] == nil && photos[.side] == nil))
            .accessibilityIdentifier("progress-estimate")
            if let estimateError {
                ErrorRow(estimateError)
            }
            if let estimate {
                ProgressEstimateNote(outcome: estimate)
            }
        } footer: {
            Text(own
                ? "Sends these photos to \(provider), on your own key, to estimate waist, hips and chest. Nothing is saved until you save the check."
                : "Sends these photos to \(provider) to estimate waist, hips and chest. Nothing is saved until you save the check.")
        }
    }

    private var measurementsSection: some View {
        Section {
            DatePicker("Date", selection: $draft.measuredOn, in: ...Date.now, displayedComponents: .date)
            ForEach(ProgressCheckDraft.Field.allCases) { field in
                HStack {
                    Text(field.title)
                    // No placeholder: the unit beside the field already says
                    // what goes in it.
                    TextField(field.title, text: Binding(get: { draft.values[field] ?? "" }, set: { draft.values[field] = $0 }),
                              prompt: Text(verbatim: ""))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("progress-\(field.rawValue)")
                    Text(field.unit).foregroundStyle(.secondary)
                }
                .foregroundStyle(draft.invalidFields.contains(field) ? .red : .primary)
            }
        } header: {
            Text("Measurements")
        } footer: {
            Text("Waist: at the navel, relaxed, tape level.")
        }
    }

    private func runEstimate() async {
        estimating = true
        defer { estimating = false }
        do {
            let result = try await store.estimate(photos)
            estimate = draft.apply(result.estimate)
            estimateError = nil
        } catch {
            estimate = nil
            estimateError = error.localizedDescription
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await store.save(draft, photos: photos)
            // Today's figure takes its shape from the new check.
            router.dataChanged()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// What an estimate did, under its button. Labelled an estimate every time:
/// the person is about to save these numbers as theirs.
private struct ProgressEstimateNote: View {
    let outcome: ProgressCheckDraft.EstimateOutcome

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Estimate, not a measurement · \(ProgressCheckText.confidence(outcome.confidence))")
                .font(.subheadline.weight(.medium))
            if !outcome.notes.isEmpty {
                Text(outcome.notes).font(.subheadline)
            }
            Group {
                if outcome.filled > 0 {
                    Text("Empty fields were filled in. Check them against a tape if you can, then save.")
                } else if outcome.kept == 0 {
                    Text("Nothing could be estimated from these photos.")
                }
                if outcome.kept > 0 {
                    Text("Numbers you had already entered were kept.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progress-estimate-note")
    }
}

/// One pose: the last photo for comparison, and the new one. A tap offers
/// the library or the camera; the photo is shrunk to a JPEG before it is
/// kept, which also drops its location.
private struct ProgressPoseSlot: View {
    let pose: ProgressPose
    let last: Components.Schemas.ProgressPhoto?
    @Binding var photo: Data?
    let onError: (String) -> Void

    /// The longest side a photo is sent at, as the web sends it.
    static let longestSide: CGFloat = 1600

    @State private var choosing = false
    @State private var browsing = false
    @State private var picked: PhotosPickerItem?
    @State private var shooting = false
    @State private var preparing = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pose.title).font(.body.weight(.medium))
                if !pose.isRequired {
                    Text("Optional").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            frame(caption: "Last") {
                if let last {
                    ProgressPhotoThumbnail(url: last.url)
                } else {
                    placeholder("No earlier photo", systemImage: nil)
                }
            }
            Button {
                choosing = true
            } label: {
                frame(caption: "Now") {
                    if let photo, let image = UIImage(data: photo) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .clipShape(.rect(cornerRadius: NorthRadius.small))
                    } else {
                        placeholder(preparing ? "Preparing…" : "Take or choose", systemImage: "camera")
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pose-\(pose.rawValue)")
        }
        .confirmationDialog(pose.title, isPresented: $choosing) {
            Button("Photo Library") { browsing = true }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") { shooting = true }
            }
            if photo != nil {
                Button("Remove Photo", role: .destructive) { photo = nil }
            }
        }
        .photosPicker(isPresented: $browsing, selection: $picked, matching: .images)
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task { await read(item) }
        }
        .fullScreenCover(isPresented: $shooting) {
            CameraCapture { image in
                shooting = false
                guard let image else { return }
                Task { await keep(ImportFile.photo(image, name: pose.rawValue, longestSide: Self.longestSide)) }
            }
            .ignoresSafeArea()
        }
    }

    private func frame(caption: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 2) {
            content().frame(width: 60, height: 80)
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func placeholder(_ text: LocalizedStringKey, systemImage: String?) -> some View {
        RoundedRectangle(cornerRadius: NorthRadius.small)
            .strokeBorder(
                .secondary.opacity(0.4),
                style: StrokeStyle(lineWidth: 1, dash: systemImage == nil ? [] : [4])
            )
            .overlay {
                VStack(spacing: 2) {
                    if let systemImage { Image(systemName: systemImage) }
                    Text(text).font(.caption2).multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding(4)
            }
    }

    private func read(_ item: PhotosPickerItem) async {
        defer { picked = nil }
        preparing = true
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            preparing = false
            return onError(String(localized: "That photo couldn't be read."))
        }
        await keep(ImportFile.photo(data: data, name: pose.rawValue, longestSide: Self.longestSide))
    }

    private func keep(_ file: ImportFile?) async {
        preparing = false
        guard let file else { return onError(String(localized: "That photo couldn't be read.")) }
        photo = file.data
    }
}
