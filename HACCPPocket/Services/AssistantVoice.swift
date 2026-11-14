//
//  AssistantVoice.swift
//  HACCPPocket
//
//  Une belle voix quand le réseau est là, une voix fiable sinon.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI DEUX MOTEURS ET PAS UN
//  ─────────────────────────────────────────────────────────────────────────
//
//  La voix en ligne est nettement plus agréable, et c'est une vraie raison
//  de la préférer : un assistant qu'on écoute volontiers est un assistant
//  dont on se sert. Mais une cuisine est l'endroit le moins sûr du monde
//  pour un réseau — chambre froide, sous-sol, box saturée en plein service.
//
//  Basculer entièrement en ligne reviendrait donc à rendre l'assistant muet
//  précisément quand il sert. La voix embarquée reste sous la main : si le
//  réseau manque, si la clé est refusée, si le quota est épuisé, la phrase
//  est dite quand même. L'utilisateur entend une voix moins belle, jamais
//  le silence.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUI NE REPART JAMAIS DEUX FOIS
//  ─────────────────────────────────────────────────────────────────────────
//
//  Chaque phrase synthétisée en ligne est gardée sur l'appareil. Les
//  quatre-vingts phrases fixes de l'assistant ne sont donc payées qu'une
//  fois, et deviennent ensuite instantanées : plus d'attente réseau sur
//  « Quelle température ? », qui revient dix fois par service.
//

import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class AssistantVoice {

    // MARK: - Réglages partagés avec l'écran des réglages

    enum Key {
        static let online = "haccp.voice.online"
        static let voiceID = "haccp.voice.id"
        static let quality = "haccp.voice.quality"
    }

    private(set) var isSpeaking = false

    /// Pourquoi aucune voix ne fonctionne. `nil` quand au moins une marche.
    private(set) var unavailableReason: String?

    /// Le dernier échec en ligne, pour le dire sans rien bloquer.
    ///
    /// Un quota épuisé ou une clé refusée ne doit pas faire taire
    /// l'assistant ; il doit se voir dans les réglages, pas en alerte au
    /// milieu d'un service.
    private(set) var lastOnlineFailure: String?

    /// Vrai quand la dernière phrase est venue du réseau.
    private(set) var lastSpokenWasOnline = false

    var isAvailable: Bool { unavailableReason == nil }

    @ObservationIgnored private let local = PiperNarrator()
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var playbackDelegate: PlaybackDelegate?

    // MARK: - Préparation

    func prepare() async {
        await local.prepare()
        refreshAvailability()
    }

    private func refreshAvailability() {
        // Une seule des deux suffit à parler.
        if usesOnline || local.isAvailable {
            unavailableReason = nil
        } else {
            unavailableReason = local.unavailableReason
                ?? "Aucune voix disponible sur cet appareil."
        }
    }

    private var usesOnline: Bool {
        // Absent des réglages, on considère la voix en ligne souhaitée :
        // elle ne servira de toute façon que si une clé existe.
        let wanted = UserDefaults.standard.object(forKey: Key.online) as? Bool ?? true
        return wanted && VoiceKeychain.hasKey
    }

    private var voiceID: String {
        UserDefaults.standard.string(forKey: Key.voiceID) ?? ElevenLabsVoice.defaultVoiceID
    }

    private var quality: ElevenLabsVoice.Quality {
        ElevenLabsVoice.Quality(
            rawValue: UserDefaults.standard.string(forKey: Key.quality) ?? ""
        ) ?? .natural
    }

    // MARK: - Parler

    /// Prononce une phrase et ne rend la main qu'à la fin.
    ///
    /// L'attente permet d'enchaîner question et réponse sans se couper la
    /// parole. Une erreur n'est jamais propagée : au pire on se tait.
    func speak(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        stop()

        if let file = await onlineAudio(for: trimmed) {
            lastSpokenWasOnline = true
            isSpeaking = true
            defer { isSpeaking = false }
            await play(file)
            return
        }

        guard let file = await local.audioFile(for: trimmed) else {
            refreshAvailability()
            return
        }

        lastSpokenWasOnline = false
        isSpeaking = true
        defer { isSpeaking = false }
        await play(file)
    }

    /// Le son venu du réseau, ou du cache, ou rien.
    private func onlineAudio(for text: String) async -> URL? {
        guard usesOnline, let key = VoiceKeychain.apiKey else { return nil }

        let model = quality.rawValue

        // Déjà payée une fois : on ne la repaie pas, et on ne l'attend pas.
        if let cached = VoiceCache.existing(for: text, voiceID: voiceID, quality: model) {
            lastOnlineFailure = nil
            return cached
        }

        do {
            let data = try await ElevenLabsVoice.synthesize(
                text, voiceID: voiceID, quality: quality, key: key
            )
            lastOnlineFailure = nil
            return VoiceCache.store(data, for: text, voiceID: voiceID, quality: model)
        } catch {
            // On note la raison et on laisse la voix embarquée prendre le
            // relais : un quota épuisé ne doit pas rendre l'assistant muet.
            lastOnlineFailure = (error as? ElevenLabsVoice.Failure)?.errorDescription
                ?? error.localizedDescription
            return nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playbackDelegate = nil
        local.stop()
        isSpeaking = false
    }

    // MARK: - Essai depuis les réglages

    /// Dit une phrase d'exemple et rend ce qui s'est passé.
    ///
    /// Utilisé par l'écran des réglages : essayer une voix avant de la
    /// choisir évite de découvrir en plein service qu'elle ne convient pas.
    func test() async -> String {
        // L'écran des réglages n'a pas chargé le moteur embarqué : sans
        // cela, un essai sans réseau ne dirait rien du tout.
        await prepare()

        let phrase = "Frigo cuisine, trois degrés. C'est dans la plage. J'enregistre ?"
        await speak(phrase)

        if let failure = lastOnlineFailure {
            return "\(failure) La voix embarquée a pris le relais."
        }
        return lastSpokenWasOnline
            ? "Voix en ligne. Cette phrase est maintenant gardée sur l'appareil."
            : "Voix embarquée."
    }

    // MARK: - Lecture

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

    /// `AVAudioPlayer` exige un délégué `NSObject`, qu'une classe
    /// `@Observable` ne peut pas être. D'où cette passerelle.
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
