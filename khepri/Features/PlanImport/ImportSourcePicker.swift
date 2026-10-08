import PhotosUI
import SwiftUI
import UIKit

/// Where an import comes from: Files, the photo library, or the camera.
///
/// Attach to the view that offers the import; set `isPresented` to ask, and
/// `onPick` receives the file ready to upload.
struct ImportSourcePicker: ViewModifier {
    @Binding var isPresented: Bool
    let onPick: (ImportFile) -> Void
    let onError: (String) -> Void

    @State private var browsingFiles = false
    @State private var choosingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var takingPhoto = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Import a plan from", isPresented: $isPresented, titleVisibility: .visible) {
                Button("Files") { browsingFiles = true }
                Button("Photo Library") { choosingPhoto = true }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") { takingPhoto = true }
                }
            } message: {
                Text("PDF, Word, text, CSV or Excel (.xlsx), JSON, or a photo of a printed plan. Up to 10 MB.")
            }
            .fileImporter(isPresented: $browsingFiles, allowedContentTypes: ImportFile.fileTypes) { result in
                do {
                    guard let file = try ImportFile.picked(result.get()) else {
                        return onError("That file couldn't be read.")
                    }
                    deliver(file)
                } catch {
                    onError(error.localizedDescription)
                }
            }
            .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images)
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    defer { photo = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data),
                          let file = ImportFile.photo(image)
                    else { return onError("That photo couldn't be read.") }
                    deliver(file)
                }
            }
            .fullScreenCover(isPresented: $takingPhoto) {
                CameraCapture { image in
                    takingPhoto = false
                    guard let image else { return }
                    guard let file = ImportFile.photo(image) else { return onError("That photo couldn't be read.") }
                    deliver(file)
                }
                .ignoresSafeArea()
            }
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
}

/// The system camera, for photographing a printed plan. SwiftUI has no camera
/// view of its own.
struct CameraCapture: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
