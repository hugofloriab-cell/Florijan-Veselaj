//
//  QRScannerView.swift
//  HACCPPocket
//
//  Lecture du QR code d'une étiquette pour rouvrir la fiche du produit.
//
//  ⚠️ Deux conditions doivent être réunies pour que la caméra fonctionne, et
//  l'oubli de l'une ou l'autre donne exactement le même symptôme — un écran
//  noir, sans message :
//
//   1. La clé « Privacy - Camera Usage Description » doit exister dans la
//      cible Xcode. Sans elle, l'application est arrêtée par le système au
//      moment où elle touche la caméra.
//   2. L'autorisation doit avoir été demandée à l'utilisateur. Sans elle, la
//      session démarre, l'aperçu reste noir, et aucun code n'est jamais lu.
//
//  Cet écran traite le second point et explique le premier.
//

import SwiftUI
import AVFoundation
import UIKit

// MARK: - Écran

struct QRScannerView: View {

    @Environment(\.dismiss) private var dismiss

    /// Reçoit la chaîne brute lue dans le QR.
    let onScan: (String) -> Void

    @State private var permission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isRequesting = false

    private var isCameraAvailable: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    /// La cible Xcode déclare-t-elle la raison d'usage de la caméra ?
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// POURQUOI CE CONTRÔLE EXISTE
    /// ─────────────────────────────────────────────────────────────────────
    ///
    /// Sans la clé `NSCameraUsageDescription`, iOS ne refuse pas l'accès : il
    /// **arrête l'application** à la seconde où `requestAccess` est appelé.
    /// Pas d'alerte, pas d'erreur récupérable, pas de `try` qui tienne — le
    /// processus est tué par le système.
    ///
    /// Du point de vue de l'utilisateur, ça ressemble exactement à un plantage
    /// de l'application, alors que le code est correct et qu'il manque une
    /// ligne dans les réglages de la cible Xcode.
    ///
    /// On vérifie donc la présence de la clé AVANT de demander quoi que ce
    /// soit. Si elle manque, l'écran l'explique au lieu de disparaître.
    private var hasCameraUsageDescription: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String
        return !(value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasCameraUsageDescription {
                    misconfiguredView
                } else if !isCameraAvailable {
                    unavailableView
                } else {
                    switch permission {
                    case .authorized:
                        scanner
                    case .notDetermined:
                        permissionPrompt
                    case .denied, .restricted:
                        deniedView
                    @unknown default:
                        permissionPrompt
                    }
                }
            }
            .navigationTitle("Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .task {
                // Une autorisation accordée depuis les réglages iOS pendant
                // que l'écran est ouvert doit être prise en compte.
                guard hasCameraUsageDescription else { return }
                permission = AVCaptureDevice.authorizationStatus(for: .video)
                if permission == .notDetermined { await requestAccess() }
            }
        }
    }

    // MARK: - Le scanner

    private var scanner: some View {
        ZStack {
            CameraScanner { code in
                onScan(code)
                dismiss()
            }
            .ignoresSafeArea()

            viewfinder
        }
    }

    // MARK: - Les cas où il ne se passe rien

    private var unavailableView: some View {
        ContentUnavailableView {
            Label("Caméra indisponible", systemImage: "camera.metering.unknown")
        } description: {
            Text("Le scan nécessite un appareil réel : le simulateur n'a pas de caméra. Testez sur votre iPhone.")
        }
    }

    /// Affiché quand la clé manque dans la cible Xcode.
    ///
    /// Ce message ne s'adresse pas au restaurateur mais à celui qui construit
    /// l'application : c'est une erreur de configuration, pas un incident
    /// d'usage. Il ne peut apparaître qu'en développement — une cible sans
    /// cette clé est refusée à la publication sur l'App Store.
    private var misconfiguredView: some View {
        ContentUnavailableView {
            Label("Caméra non déclarée", systemImage: "exclamationmark.triangle")
        } description: {
            Text("""
            La cible Xcode ne déclare pas pourquoi l'application utilise la caméra. Sans cette déclaration, iOS arrête l'application dès qu'on demande l'autorisation.

            À faire une seule fois, dans Xcode :
            cible HACCPPocket → onglet Info → ajouter la clé « Privacy - Camera Usage Description », avec une phrase expliquant l'usage.
            """)
        }
    }

    private var permissionPrompt: some View {
        ContentUnavailableView {
            Label("Autoriser la caméra", systemImage: "camera")
        } description: {
            Text("Le scan de QR code et de code-barres a besoin de la caméra. Rien n'est enregistré ni envoyé : l'image sert uniquement à lire le code.")
        } actions: {
            Button {
                Task { await requestAccess() }
            } label: {
                if isRequesting {
                    ProgressView()
                } else {
                    Text("Autoriser")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequesting)
        }
    }

    private var deniedView: some View {
        ContentUnavailableView {
            Label("Caméra refusée", systemImage: "camera.badge.ellipsis")
        } description: {
            Text("L'accès à la caméra a été refusé. Ouvrez les réglages de l'iPhone, puis HACCP Pocket, et activez Appareil photo.")
        } actions: {
            Button("Ouvrir les réglages") { openSystemSettings() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Autorisation

    private func requestAccess() async {
        // Deuxième filet : `requestAccess` sans la clé tue le processus, et
        // ce bouton est atteignable par un chemin que le contrôle d'affichage
        // ne couvrirait pas.
        guard hasCameraUsageDescription else { return }

        isRequesting = true
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        permission = granted ? .authorized : .denied
        isRequesting = false
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Cadre de visée et consigne, superposés au flux vidéo.
    private var viewfinder: some View {
        VStack {
            Spacer()

            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 3)
                .frame(width: 240, height: 240)

            Spacer()

            Text("Visez un QR d'étiquette ou le code-barres du produit")
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
        // QR pour nos étiquettes, EAN pour les produits, GS1-128 et DataMatrix
        // pour les cartons fournisseurs qui portent DLC et numéro de lot.
        output.metadataObjectTypes = [
            .qr, .dataMatrix, .pdf417,
            .ean13, .ean8, .upce,
            .code128, .code39, .itf14
        ]

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
