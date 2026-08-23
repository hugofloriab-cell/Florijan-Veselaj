//
//  QRScannerView.swift
//  HACCPPocket
//
//  Lecture du QR code d'une étiquette pour rouvrir la fiche du produit.
//

import SwiftUI
import AVFoundation
import UIKit

// MARK: - Écran

struct QRScannerView: View {

    @Environment(\.dismiss) private var dismiss

    /// Reçoit la chaîne brute lue dans le QR.
    let onScan: (String) -> Void

    @State private var errorMessage: String?

    private var isCameraAvailable: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if isCameraAvailable {
                    ZStack {
                        CameraScanner { code in
                            onScan(code)
                            dismiss()
                        }
                        .ignoresSafeArea()

                        viewfinder
                    }
                } else {
                    ContentUnavailableView(
                        "Caméra indisponible",
                        systemImage: "camera.metering.unknown",
                        description: Text("Le scan de QR code nécessite un appareil réel : le simulateur n'a pas de caméra.")
                    )
                }
            }
            .navigationTitle("Scanner une étiquette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }

    /// Cadre de visée et consigne, superposés au flux vidéo.
    private var viewfinder: some View {
        VStack {
            Spacer()

            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 3)
                .frame(width: 240, height: 240)

            Spacer()

            Text("Visez le QR code de l'étiquette")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(.bottom, 40)
        }
    }
}

// MARK: - Passerelle AVFoundation

private struct CameraScanner: UIViewControllerRepresentable {

    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {
        controller.onScan = onScan
    }
}

/// Contrôleur minimal : une session de capture et une couche d'aperçu.
private final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var onScan: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    /// Évite d'appeler la fermeture des dizaines de fois pour un même code.
    private var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasScanned = false
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    /// `startRunning()` est bloquant : il ne doit jamais tourner sur le thread
    /// principal, sous peine de figer l'interface une seconde.
    private func startSession() {
        guard !session.isRunning else { return }
        Task.detached(priority: .userInitiated) { [session] in
            session.startRunning()
        }
    }

    private func stopSession() {
        guard session.isRunning else { return }
        Task.detached(priority: .userInitiated) { [session] in
            session.stopRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasScanned,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else {
            return
        }

        hasScanned = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onScan?(value)
    }
}
