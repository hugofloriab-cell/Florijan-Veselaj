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
    ///
    /// La clé `NSCameraUsageDescription` est exigée en plus du matériel :
    /// présenter cet écran sans elle fait arrêter l'application par iOS, ce
    /// qui ressemble à un plantage alors que c'est un réglage manquant dans
    /// la cible Xcode. Mieux vaut masquer le bouton que perdre l'utilisateur.
    static var isAvailable: Bool {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return false }
        let reason = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String
        return !(reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
