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

// Le paquet Swift de sherpa-onnx ne livre que le framework C/C++ ; l'enrobage
// Swift du dépôt n'est qu'un exemple, à recopier. Plutôt que de recopier
// 2 200 lignes dont la signature change à chaque version, on appelle l'API C
// directement, ci-dessous dans `PiperEngine`. Le nom du module diffère selon
// la distribution du framework, d'où les deux tentatives.
#if canImport(SherpaOnnx) || canImport(SherpaOnnxC)
import SherpaOnnx
#elseif canImport(SherpaOnnxC)
import SherpaOnnxC
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
        #if canImport(SherpaOnnx) || canImport(SherpaOnnxC)
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

        #if canImport(SherpaOnnx) || canImport(SherpaOnnxC)
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

    #if canImport(SherpaOnnx) || canImport(SherpaOnnxC)
    /// Le moteur côté C. Type opaque : on ne voit qu'une adresse.
    ///
    /// Il n'est jamais libéré, et c'est volontaire : l'objet est créé une
    /// seule fois et vit aussi longtemps que l'application. Écrire un `deinit`
    /// ici n'apporterait rien et compliquerait la gestion d'isolation.
    private var tts: OpaquePointer?
    #endif

    private var isLoaded = false

    /// Charge le modèle. Renvoie `nil` si tout va bien, sinon la raison.
    func load(from folder: URL) async -> String? {
        #if canImport(SherpaOnnx) || canImport(SherpaOnnxC)
        guard !isLoaded else { return nil }

        guard let files = Self.locateFiles(in: folder) else {
            return "Fichiers de voix incomplets dans « \(folder.lastPathComponent) »."
        }

        // Les chaînes passées au C sont recopiées à la main puis libérées à la
        // sortie. On ne se repose pas sur la durée de vie d'une chaîne Swift :
        // elle n'est garantie que pendant l'appel, et la configuration est
        // assemblée en plusieurs étapes avant d'être transmise.
        var allocated: [UnsafeMutablePointer<CChar>] = []
        defer { allocated.forEach { free($0) } }

        func cString(_ value: String) -> UnsafePointer<CChar> {
            let copy = strdup(value)!
            allocated.append(copy)
            return UnsafePointer(copy)
        }

        // Les structures C sont créées à zéro puis remplies champ par champ.
        //
        // C'est le point important : l'initialiseur complet de ces structures
        // change à chaque version de sherpa-onnx, qui ajoute des moteurs
        // (matcha, kokoro, kitten…). Remplir seulement les champs utiles rend
        // ce code valide quelle que soit la version du framework installée.
        var vits = SherpaOnnxOfflineTtsVitsModelConfig()
        vits.model = cString(files.model)
        vits.tokens = cString(files.tokens)
        vits.data_dir = cString(files.espeakData)
        vits.lexicon = cString("")
        vits.dict_dir = cString("")
        vits.noise_scale = 0.667
        vits.noise_scale_w = 0.8
        vits.length_scale = 1.0

        var model = SherpaOnnxOfflineTtsModelConfig()
        model.vits = vits
        // Deux fils : assez pour rester bref sur une phrase courte, pas assez
        // pour faire chauffer le téléphone en plein service.
        model.num_threads = 2
        model.debug = 0
        model.provider = cString("cpu")

        var config = SherpaOnnxOfflineTtsConfig()
        config.model = model
        config.rule_fsts = cString("")
        config.rule_fars = cString("")
        config.max_num_sentences = 1
        // Durée du silence entre deux phrases. À zéro, le débit est précipité.
        config.silence_scale = 0.2

        tts = withUnsafePointer(to: &config) { SherpaOnnxCreateOfflineTts($0) }

        guard tts != nil else {
            // Deux causes possibles, et une seule se voit dans la console.
            //
            // Soit les fichiers sont illisibles, soit le framework a été
            // compilé sans la synthèse vocale — dans ce cas sherpa-onnx écrit
            // « TTS is not enabled. Please rebuild sherpa-onnx » dans la
            // console Xcode. Le message ci-dessous invite à aller voir.
            return "Voix refusée par le moteur. Voir la console Xcode."
        }

        isLoaded = true
        return nil
        #else
        return "Moteur de synthèse absent de cette version."
        #endif
    }

    /// Produit un fichier WAV temporaire, ou `nil` en cas d'échec.
    func synthesize(_ text: String) async -> URL? {
        #if canImport(SherpaOnnx) || canImport(SherpaOnnxC)
        guard let tts else { return nil }

        // `SherpaOnnxOfflineTtsGenerate` est marquée obsolète depuis la 1.13 au
        // profit d'une variante qui prend une structure de configuration. On
        // garde l'ancienne volontairement : elle existe dans toutes les
        // versions du framework, la nouvelle non. Xcode affichera un
        // avertissement, pas une erreur.
        guard let audio = text.withCString({ pointer in
            SherpaOnnxOfflineTtsGenerate(tts, pointer, 0, 1.0)
        }) else { return nil }

        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }

        guard audio.pointee.n > 0, let samples = audio.pointee.samples else {
            return nil
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("piper-\(UUID().uuidString).wav")

        let written = url.path.withCString { filename in
            SherpaOnnxWriteWave(samples, audio.pointee.n,
                                audio.pointee.sample_rate, filename)
        }

        guard written == 1 else { return nil }
        return url
        #else
        return nil
        #endif
    }

    // MARK: - Les trois pièces d'une voix

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
