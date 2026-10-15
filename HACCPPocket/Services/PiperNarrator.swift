//
//  PiperNarrator.swift
//  HACCPPocket
//
//  La voix de l'assistant, par un moteur neuronal embarqué.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI PAS CELLE D'APPLE
//  ─────────────────────────────────────────────────────────────────────────
//
//  `AVSpeechSynthesizer` a été essayé pendant plusieurs semaines, voix
//  Premium téléchargée comprise, et jugé trop mécanique. Les voix de Siri
//  sont réservées aux applications d'Apple — aucune clé de configuration,
//  aucun droit, aucune extension n'y donne accès. Apple Intelligence ne
//  produit pas de parole : son modèle génère du texte.
//
//  Le seul levier restant était un moteur tiers. sherpa-onnx fait tourner
//  un modèle VITS français de Piper, entièrement sur l'appareil, sans
//  réseau ni coût récurrent — les deux règles du projet depuis le départ.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUE ÇA COÛTE, HONNÊTEMENT
//  ─────────────────────────────────────────────────────────────────────────
//
//  Environ soixante-trois mégaoctets de modèle, plus le framework. La
//  synthèse d'une phrase prend quelques centaines de millisecondes : c'est
//  imperceptible sur une question courte, et c'est pour ça que l'assistant
//  ne prononce que ses propres phrases — jamais un mode opératoire entier.
//
//  ─────────────────────────────────────────────────────────────────────────
//  LE MOTEUR N'EST JAMAIS INDISPENSABLE
//  ─────────────────────────────────────────────────────────────────────────
//
//  Tout ici échoue en silence et sans conséquence. Si les fichiers de voix
//  manquent, si le modèle refuse de se charger, si la synthèse rate :
//  l'assistant continue d'écrire ses questions à l'écran, et l'application
//  fonctionne exactement comme avant. Une voix est un confort, jamais une
//  condition — surtout dans une application où tout doit rester lisible.
//

import AVFoundation
import Foundation
import Observation

#if canImport(SherpaOnnx)
import SherpaOnnx
#endif

@MainActor
@Observable
final class PiperNarrator {

    /// Nom du dossier de voix embarqué dans l'application.
    ///
    /// Il doit être ajouté à Xcode **comme référence de dossier** — le
    /// dossier bleu — et non comme groupe : `espeak-ng-data` contient des
    /// milliers de fichiers répartis en sous-dossiers, et le moteur a besoin
    /// de cette arborescence intacte. Ajouté en groupe, tout serait aplati
    /// et la phonétisation échouerait.
    static let voiceFolderName = "PiperVoice"

    private(set) var isSpeaking = false

    /// Pourquoi la voix ne fonctionne pas, quand c'est le cas.
    ///
    /// Affiché dans l'écran de l'assistant, jamais sous forme d'alerte : on
    /// ne bloque pas un cuisinier pour un problème de confort.
    private(set) var unavailableReason: String?

    private let engine = PiperEngine()
    private var player: AVAudioPlayer?
    private var playbackDelegate: PlaybackDelegate?

    /// Le moteur est-il utilisable ?
    ///
    /// La réponse demande de charger le modèle, donc elle prend un instant
    /// la première fois. L'écran s'en sert pour savoir s'il annonce une voix.
    func prepare() async {
        #if canImport(SherpaOnnx)
        guard let folder = Self.voiceFolderURL() else {
            unavailableReason = "Voix française absente de l'application."
            return
        }
        unavailableReason = await engine.load(from: folder)
        #else
        unavailableReason = "Moteur de synthèse absent de cette version."
        #endif
    }

    var isAvailable: Bool { unavailableReason == nil }

    // MARK: - Parler

    /// Prononce une phrase et ne rend la main qu'à la fin.
    ///
    /// L'attente permet d'enchaîner question et réponse sans se couper la
    /// parole. Une erreur n'est jamais propagée : au pire on se tait.
    func speak(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isAvailable else { return }

        #if canImport(SherpaOnnx)
        stop()

        guard let wavURL = await engine.synthesize(trimmed) else { return }

        isSpeaking = true
        defer { isSpeaking = false }

        await play(wavURL)
        #endif
    }

    func stop() {
        player?.stop()
        player = nil
        playbackDelegate = nil
        isSpeaking = false
    }

    // MARK: - Lecture du fichier produit

    private func play(_ url: URL) async {
        prepareAudioSession()

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                do {
                    let audioPlayer = try AVAudioPlayer(contentsOf: url)
                    let delegate = PlaybackDelegate { continuation.resume() }

                    audioPlayer.delegate = delegate
                    self.player = audioPlayer
                    self.playbackDelegate = delegate

                    if !audioPlayer.play() {
                        delegate.finish()
                    }
                } catch {
                    continuation.resume()
                }
            }
        } onCancel: {
            Task { @MainActor in self.stop() }
        }
    }

    /// `.playback` pour s'entendre même sonnerie coupée, `.mixWithOthers`
    /// pour ne pas arrêter la musique de la cuisine.
    private func prepareAudioSession() {
        #if canImport(UIKit)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true, options: [])
        #endif
    }

    // MARK: - Localisation des fichiers

    /// Le dossier de voix dans le paquet de l'application.
    nonisolated static func voiceFolderURL() -> URL? {
        Bundle.main.url(forResource: voiceFolderName, withExtension: nil)
    }

    // MARK: - Fin de lecture

    /// `AVAudioPlayer` exige un délégué `NSObject`, qu'une classe
    /// `@Observable` ne peut pas être. D'où cette passerelle, comme pour la
    /// synthèse d'Apple en son temps.
    private final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {

        /// Appelée une seule fois, que la lecture finisse ou soit coupée.
        nonisolated(unsafe) private var onFinish: (() -> Void)?

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func finish() {
            let callback = onFinish
            onFinish = nil
            callback?()
        }

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            finish()
        }

        func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
            finish()
        }
    }
}

// MARK: - Le moteur, à l'écart du fil principal

/// Le modèle et la synthèse vivent dans un acteur.
///
/// Charger soixante-trois mégaoctets et produire un signal audio sont des
/// opérations lourdes : les laisser sur le fil principal ferait sauter
/// l'affichage. L'acteur garantit aussi qu'une seule synthèse tourne à la
/// fois — le moteur n'est pas réentrant.
private actor PiperEngine {

    #if canImport(SherpaOnnx)
    private var tts: SherpaOnnxOfflineTtsWrapper?
    #endif

    private var isLoaded = false

    /// Charge le modèle. Renvoie `nil` si tout va bien, sinon la raison.
    func load(from folder: URL) async -> String? {
        #if canImport(SherpaOnnx)
        guard !isLoaded else { return nil }

        guard let files = Self.locateFiles(in: folder) else {
            return "Fichiers de voix incomplets dans « \(folder.lastPathComponent) »."
        }

        let vits = sherpaOnnxOfflineTtsVitsModelConfig(
            model: files.model,
            tokens: files.tokens,
            dataDir: files.espeakData
        )

        // Deux fils : assez pour rester bref sur une phrase courte, pas assez
        // pour faire chauffer le téléphone en plein service.
        let model = sherpaOnnxOfflineTtsModelConfig(numThreads: 2, vits: vits)

        // `var` obligatoire : `withUnsafePointer(to:)` veut une adresse.
        var config = sherpaOnnxOfflineTtsConfig(model: model)

        tts = withUnsafePointer(to: &config) { pointer in
            SherpaOnnxOfflineTtsWrapper(config: pointer)
        }
        isLoaded = true
        return nil
        #else
        return "Moteur de synthèse absent de cette version."
        #endif
    }

    /// Produit un fichier WAV temporaire, ou `nil` en cas d'échec.
    func synthesize(_ text: String) async -> URL? {
        #if canImport(SherpaOnnx)
        guard let tts else { return nil }

        let audio = tts.generate(text: text, sid: 0, speed: 1.0)
        guard audio.n > 0 else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("piper-\(UUID().uuidString).wav")

        guard audio.save(filename: url.path) == 1 else { return nil }
        return url
        #else
        return nil
        #endif
    }

    // MARK: - Trouver les trois pièces

    private struct VoiceFiles {
        let model: String
        let tokens: String
        let espeakData: String
    }

    /// Cherche le modèle, les jetons et les données de phonétisation.
    ///
    /// La recherche est volontairement souple : les archives de sherpa-onnx
    /// changent de nom d'une voix à l'autre, et imposer un nom de fichier
    /// exact condamnerait à une correction de code à chaque changement de
    /// voix. On cherche ce qui finit par `.onnx`, le `tokens.txt`, et le
    /// dossier `espeak-ng-data`, où qu'ils soient.
    private static func locateFiles(in folder: URL) -> VoiceFiles? {
        let manager = FileManager.default
        guard let walker = manager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return nil }

        var model: URL?
        var tokens: URL?
        var espeak: URL?

        for case let url as URL in walker {
            switch url.lastPathComponent {
            case "tokens.txt":
                tokens = url
            case "espeak-ng-data":
                espeak = url
                // Inutile de descendre dans ses milliers de fichiers.
                walker.skipDescendants()
            default:
                if url.pathExtension == "onnx" { model = url }
            }
        }

        guard let model, let tokens, let espeak else { return nil }
        return VoiceFiles(
            model: model.path,
            tokens: tokens.path,
            espeakData: espeak.path
        )
    }
}
