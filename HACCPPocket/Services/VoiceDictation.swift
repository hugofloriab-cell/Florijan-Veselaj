//
//  VoiceDictation.swift
//  HACCPPocket
//
//  La dictée : transformer ce qu'on dit en texte, sans réseau.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI CETTE BRIQUE EST LIVRÉE SEULE, AVANT L'ASSISTANT
//  ─────────────────────────────────────────────────────────────────────────
//
//  Le projet d'assistant vocal repose sur trois couches : entendre,
//  comprendre, agir. Les deux dernières sont du logiciel — elles marcheront
//  ou ne compileront pas, et ça se corrige. La première dépend du monde
//  réel : une hotte qui souffle, un batteur, un coup de feu, un accent.
//
//  Si la transcription rend de la bouillie en service, tout le reste est
//  inutile, aussi bien construit soit-il. Autant le savoir avant d'avoir
//  bâti par-dessus.
//
//  ─────────────────────────────────────────────────────────────────────────
//  TOUT RESTE SUR L'APPAREIL
//  ─────────────────────────────────────────────────────────────────────────
//
//  `requiresOnDeviceRecognition` force la reconnaissance en local. Sans ce
//  réglage, iOS envoie l'audio aux serveurs d'Apple — ce qui marche mieux,
//  mais contredit la règle du projet depuis le premier jour : rien ne sort
//  de l'appareil, et l'application fonctionne dans une réserve sans réseau.
//
//  Quand le modèle français local n'est pas encore installé, l'écran le dit
//  au lieu de basculer en douce sur le réseau.
//

import AVFoundation
import Foundation
import Observation
import Speech

@MainActor
@Observable
final class VoiceDictation {

    /// Ce que l'écran a besoin de savoir, et rien de plus.
    enum State: Equatable {
        case idle
        case listening
        /// Impossible, avec la raison en clair — jamais un échec muet.
        case unavailable(String)
    }

    private(set) var state: State = .idle

    /// Le texte reconnu, mis à jour au fil de la phrase.
    private(set) var transcript = ""

    /// Niveau sonore entre 0 et 1, pour l'anneau qui pulse.
    ///
    /// Il sert autant à décorer qu'à informer : voir l'anneau rester plat
    /// pendant qu'on parle, c'est comprendre tout de suite que le micro est
    /// couvert ou que le téléphone est dans la poche.
    private(set) var level: Double = 0

    /// La reconnaissance tourne-t-elle vraiment en local ?
    private(set) var isOnDevice = false

    // MARK: - Réglages

    /// Silence toléré avant de couper tout seul.
    ///
    /// Les mains sont occupées : on ne peut pas toujours retoucher l'écran
    /// pour arrêter. Dans une cuisine bruyante le seuil n'est jamais franchi
    /// et l'arrêt reste manuel — c'est un échec sans conséquence.
    private static let silenceBeforeStop: TimeInterval = 1.8

    /// Durée maximale d'une dictée. Garde-fou contre un micro resté ouvert.
    private static let maximumDuration: TimeInterval = 45

    /// En dessous, on considère qu'il ne se passe rien.
    private static let silenceThreshold: Double = 0.02

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr_FR"))
    private let engine = AVAudioEngine()

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var watchdog: Task<Void, Never>?

    private var lastVoiceAt = Date.distantPast
    private var startedAt = Date.distantPast

    // MARK: - Diagnostic

    /// Le français est-il reconnaissable hors ligne sur cet appareil ?
    var supportsFrenchOnDevice: Bool {
        recognizer?.supportsOnDeviceRecognition ?? false
    }

    var isListening: Bool { state == .listening }

    // MARK: - Démarrage

    func start() async {
        guard state != .listening else { return }

        transcript = ""
        level = 0

        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable("La reconnaissance vocale française n'est pas disponible sur cet appareil.")
            return
        }

        guard await requestSpeechAuthorization() else {
            state = .unavailable("Autorisez la reconnaissance vocale dans Réglages → HACCP Pocket.")
            return
        }

        guard await requestMicrophone() else {
            state = .unavailable("Autorisez le micro dans Réglages → HACCP Pocket.")
            return
        }

        do {
            try beginListening(with: recognizer)
        } catch {
            state = .unavailable("Le micro n'a pas pu démarrer. Fermez les autres applications qui l'utilisent.")
        }
    }

    func stop() {
        watchdog?.cancel()
        watchdog = nil

        task?.cancel()
        task = nil

        request?.endAudio()
        request = nil

        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        // On relâche la session audio : la laisser active couperait la
        // musique de la cuisine pour rien jusqu'à la fermeture de l'app.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        level = 0
        if state == .listening { state = .idle }
    }

    func clear() {
        transcript = ""
    }

    // MARK: - Mise en écoute

    private func beginListening(with recognizer: SFSpeechRecognizer) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let audioRequest = SFSpeechAudioBufferRecognitionRequest()
        audioRequest.shouldReportPartialResults = true

        // Le local d'abord, toujours. Si le modèle français n'est pas
        // téléchargé, on le dit plutôt que d'envoyer l'audio au réseau.
        let onDevice = recognizer.supportsOnDeviceRecognition
        audioRequest.requiresOnDeviceRecognition = onDevice
        isOnDevice = onDevice

        request = audioRequest

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        // La fermeture tourne sur le fil audio, jamais sur le fil principal :
        // on n'y touche donc à rien d'isolé, on se contente d'empiler le
        // tampon et de renvoyer le niveau mesuré.
        // Capture faible obligatoire : le nœud d'entrée retient cette
        // fermeture, et une capture forte ferait un cycle `self` → moteur →
        // fermeture → `self`. On la lie une seule fois, ici, parce que
        // `[weak self]` sur une fermeture imbriquée porterait sur un
        // optionnel et ne compilerait pas.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            audioRequest.append(buffer)
            let measured = Self.loudness(of: buffer)
            guard let self else { return }
            Task { @MainActor in
                self.noteLevel(measured)
            }
        }

        engine.prepare()
        try engine.start()

        startedAt = .now
        lastVoiceAt = .now
        state = .listening

        // Le rappel arrive sur une file quelconque : on repasse sur le fil
        // principal avant de toucher à quoi que ce soit d'affiché.
        task = recognizer.recognitionTask(with: audioRequest) { [weak self] result, error in
            guard let self else { return }
            let text = result?.bestTranscription.formattedString
            let isDone = error != nil || result?.isFinal == true
            Task { @MainActor in
                if let text { self.transcript = text }
                if isDone { self.stop() }
            }
        }

        startWatchdog()
    }

    /// Coupe tout seul après un silence, ou au bout du temps maximal.
    private func startWatchdog() {
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.state == .listening else { return }

                if Date.now.timeIntervalSince(self.startedAt) > Self.maximumDuration {
                    self.stop()
                    return
                }

                let silentFor = Date.now.timeIntervalSince(self.lastVoiceAt)
                if !self.transcript.isEmpty && silentFor > Self.silenceBeforeStop {
                    self.stop()
                    return
                }
            }
        }
    }

    private func noteLevel(_ measured: Double) {
        // Lissage : sans lui l'anneau tremble au lieu de respirer.
        level = level * 0.7 + measured * 0.3
        if measured > Self.silenceThreshold {
            lastVoiceAt = .now
        }
    }

    // MARK: - Mesure du niveau

    /// Niveau sonore d'un tampon, ramené entre 0 et 1.
    ///
    /// `nonisolated` parce que cette fonction est appelée depuis le fil
    /// audio, où l'on n'a le droit de toucher à rien d'autre.
    private nonisolated static func loudness(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }

        let rms = (sum / Float(count)).squareRoot()

        // L'oreille est logarithmique, pas l'amplitude. Sans cette mise à
        // l'échelle, une voix normale ferait bouger l'anneau de trois pixels.
        let decibels = 20 * log10(max(rms, 0.000_001))
        let normalized = (Double(decibels) + 50) / 50
        return min(1, max(0, normalized))
    }

    // MARK: - Autorisations

    private func requestSpeechAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        default:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    private func requestMicrophone() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
