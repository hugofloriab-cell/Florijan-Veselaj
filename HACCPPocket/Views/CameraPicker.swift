//
//  CameraPicker.swift
//  HACCPPocket
//
//  Passerelle vers l'appareil photo. `PhotosPicker` couvre la photothèque,
//  mais la prise de vue directe passe encore par UIKit.
//

import SwiftUI

#if canImport(UIKit)
import UIKit

struct CameraPicker: UIViewControllerRepresentable {

    /// Reçoit la photo compressée en JPEG.
    let onCapture: (Data) -> Void

    /// Appelée à la fermeture, que l'utilisateur ait pris une photo ou annulé.
    /// La fermeture est pilotée par la vue appelante plutôt que par
    /// `@Environment(\.dismiss)` : l'environnement n'est pas encore disponible
    /// au moment où le coordinateur est construit.
    let onFinish: () -> Void

    /// Faux sur simulateur et sur Mac : les vues appelantes masquent alors
    /// le bouton de prise de vue.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onFinish: onFinish)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

        private let onCapture: (Data) -> Void
        private let onFinish: () -> Void

        init(onCapture: @escaping (Data) -> Void, onFinish: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                onCapture(data)
            }
            onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish()
        }
    }
}
#endif
