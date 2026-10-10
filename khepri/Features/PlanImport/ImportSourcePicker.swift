import PhotosUI
import SwiftUI
import UIKit

/// Where an import comes from: Files, the photo library, or the camera.
///
/// Attach to the view that offers the import; set `isPresented` to ask, and
/// `onPick` receives the file ready to upload.
struct ImportSourcePicker: ViewModifier {
    @Binding var isPresented: Bool
    var title = "Import a plan from"
    var message = "PDF, Word, text, CSV or Excel (.xlsx), JSON, or a photo of a printed plan. Up to 10 MB."
    let onPick: (ImportFile) -> Void
    let onError: (String) -> Void

    @State private var browsingFiles = false
    @State private var choosingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var takingPhoto = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) {
                Button("Files") { browsingFiles = true }
                Button("Photo Library") { choosingPhoto = true }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") { takingPhoto = true }
                }
            } message: {
                Text(message)
            }
            .fileImporter(isPresented: $browsingFiles, allowedContentTypes: ImportFile.fileTypes) { result in
                Task { await readFile(result) }
            }
            .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images)
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task { await readPhoto(item) }
            }
            .fullScreenCover(isPresented: $takingPhoto) {
                CameraCapture { image in
                    takingPhoto = false
                    guard let image else { return }
                    Task { await readCapture(image) }
                }
                .ignoresSafeArea()
            }
    }

    private func readFile(_ result: Result<URL, any Error>) async {
        do {
            guard let file = try await ImportFile.picked(result.get()) else {
                return onError("That file couldn't be read.")
            }
            deliver(file)
        } catch {
            onError(error.localizedDescription)
        }
    }

    private func readPhoto(_ item: PhotosPickerItem) async {
        defer { photo = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let file = await ImportFile.photo(data: data)
        else { return onError("That photo couldn't be read.") }
        deliver(file)
    }

    private func readCapture(_ image: UIImage) async {
        guard let file = await ImportFile.photo(image) else { return onError("That photo couldn't be read.") }
        deliver(file)
    }

    private func deliver(_ file: ImportFile) {
        guard file.data.count <= ImportFile.maxBytes else {
            return onError("That file is larger than 10 MB.")
        }
        onPick(file)
    }
}

extension View {
    func importSourcePicker(
        isPresented: Binding<Bool>,
        onPick: @escaping (ImportFile) -> Void,
        onError: @escaping (String) -> Void
    ) -> some View {
        modifier(ImportSourcePicker(isPresented: isPresented, onPick: onPick, onError: onError))
    }

    /// The same sources under the caller's own wording, for a picker that is
    /// not importing a plan.
    func importSourcePicker(
        _ title: String,
        message: String,
        isPresented: Binding<Bool>,
        onPick: @escaping (ImportFile) -> Void,
        onError: @escaping (String) -> Void
    ) -> some View {
        modifier(ImportSourcePicker(
            isPresented: isPresented, title: title, message: message, onPick: onPick, onError: onError
        ))
    }
}
