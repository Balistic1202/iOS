import PhotosUI
import SwiftUI

/// Rows for taking or importing a label photo. The photo is read on this device and handed back
/// in memory only; this view never stores it.
struct LabelPhotoSource: View {
    var cameraTitle = "Photograph a label"
    var importTitle = "Import a photo"
    let onRead: (_ text: String, _ image: UIImage) -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isReading = false
    @State private var message: String?

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        Group {
            if cameraAvailable {
                Button {
                    showCamera = true
                } label: {
                    Label(cameraTitle, systemImage: "camera")
                }
            } else {
                Label("\(cameraTitle) (no camera on this device)", systemImage: "camera")
                    .foregroundStyle(.secondary)
            }

            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label(importTitle, systemImage: "photo")
            }

            if isReading {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Reading the text on this device…")
                }
                .accessibilityElement(children: .combine)
            }

            if let message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
            }
        }
        .disabled(isReading)
        .onChange(of: pickerItem) {
            guard let item = pickerItem else { return }
            pickerItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    message = "That photo could not be opened. Try another one."
                    return
                }
                await read(image)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                if let image {
                    Task { await read(image) }
                }
            }
            .ignoresSafeArea()
        }
    }

    private func read(_ image: UIImage) async {
        isReading = true
        message = nil
        defer { isReading = false }
        do {
            let text = try await TextRecognizer.recognize(image)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                message = "No text could be read from that photo. Try a sharper, closer photo, or enter the label by hand."
            } else {
                onRead(text, image)
            }
        } catch {
            message = "The photo could not be read. Try again, or enter the label by hand."
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
