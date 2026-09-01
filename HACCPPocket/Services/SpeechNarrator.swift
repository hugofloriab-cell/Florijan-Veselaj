//
//  SpeechNarrator.swift
//  HACCPPocket
//
//  La voix qui commente les modes opératoires.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI UNE VOIX DE SYNTHÈSE ET NON UN ENREGISTREMENT
//  ─────────────────────────────────────────────────────────────────────────
//
//  Faire enregistrer les commentaires par une comédienne donnerait un rendu
//  supérieur, mais suppose une centaine de fichiers audio : dix-huit modes
//  opératoires, six à huit étapes chacun. Plusieurs dizaines de mégaoctets
//  ajoutés à l'application, et surtout une séance de studio à refaire à
//  chaque correction de formulation — or on en a déjà fait plusieurs.
//
//  La synthèse lit le texte des `OperationProtocol`. Corriger une phrase
//  corrige donc l'écrit ET le parlé, sans réenregistrer quoi que ce soit.
//  Tout se passe sur l'appareil : ni réseau, ni coût.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUE VAUT LA VOIX, HONNÊTEMENT
//  ─────────────────────────────────────────────────────────────────────────
//
//  iOS embarque d'origine une voix française « compacte », correcte mais
//  reconnaissable comme synthétique. Les voix « améliorée » et « premium »
//  sont nettement plus naturelles et se téléchargent gratuitement dans
//  Réglages → Accessibilité → Contenu énoncé → Voix.
//
//  Ce fichier prend automatiquement la meilleure voix installée. Il ne peut
//  pas la télécharger à la place de l'utilisateur — c'est un réglage système,
//  hors de portée d'une application. L'écran le signale une fois.
//

import AVFoundation
import Observation

@MainActor
@Observable
final class SpeechNarrator {

    /// Vitesse de lecture.
    ///
    /// La valeur par défaut d'iOS est trop rapide pour une consigne qu'on
    /// entend une seule fois, en cuisine, avec du bruit autour. On ralentit
    /// nettement : mieux vaut une phrase de plus que deux relectures.
    private static let rate: Float = 0.46

    /// Hauteur de voix, légèrement sous la normale.
    ///
    /// Une voix un peu plus grave est perçue comme plus posée et plus sûre
    /// d'elle. Descendre davantage la rendrait caverneuse.
    private static let pitch: Float = 0.96

    private let synthesizer = AVSpeechSynthesizer()
    private let coordinator = Coordinator()

    private(set) var isSpeaking = false

    /// Voix retenue, `nil` si le système n'en propose aucune en français.
    let voice: AVSpeechSynthesisVoice?

    init() {
        self.voice = Self.bestFrenchVoice()
        synthesizer.delegate = coordinator
    }

    /// La voix installée est-elle la version compacte d'origine ?
    ///
    /// Sert à proposer une fois le téléchargement d'une voix plus naturelle,
    /// sans harceler quelqu'un qui l'a déjà fait.
    var usesCompactVoice: Bool {
        guard let voice else { return false }
        return voice.quality == .default
    }

    var voiceName: String { voice?.name ?? "Voix système" }

    // MARK: - Lecture

    /// Prononce un texte et ne rend la main qu'à la fin.
    ///
    /// L'attente est ce qui règle le rythme de l'animation : une image reste
    /// affichée tant que sa phrase n'est pas terminée. Un texte long tient
    /// donc l'écran plus longtemps, ce qui est exactement ce qu'on veut.
    func speak(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        prepareAudioSession()
        stop()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice
        utterance.rate = Self.rate
        utterance.pitchMultiplier = Self.pitch
        utterance.postUtteranceDelay = 0

        isSpeaking = true
        defer { isSpeaking = false }

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                coordinator.onFinish = { continuation.resume() }
                synthesizer.speak(utterance)
            }
        } onCancel: {
            // La fermeture de l'écran ou un appui sur pause doit couper la
            // voix immédiatement : la laisser finir sa phrase dans le vide
            // est la première chose qu'on reproche à ce genre d'écran.
            Task { @MainActor in self.stop() }
        }
    }

    func stop() {
        guard synthesizer.isSpeaking || synthesizer.isPaused else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Session audio

    /// Configure la sortie audio pour que la voix s'entende.
    ///
    /// `.playback` permet la lecture même quand la sonnerie est coupée :
    /// c'est ce qu'on attend d'une vidéo qu'on vient délibérément lancer.
    /// `.mixWithOthers` évite de couper la musique du fond de cuisine.
    private func prepareAudioSession() {
        #if canImport(UIKit)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true, options: [])
        #endif
    }

    // MARK: - Choix de la voix

    /// La meilleure voix française installée, féminine de préférence.
    ///
    /// L'ordre de préférence est explicite : qualité d'abord — une voix
    /// premium féminine bat une compacte féminine —, puis le genre demandé,
    /// puis le français de France avant les autres variantes.
    private static func bestFrenchVoice() -> AVSpeechSynthesisVoice? {
        let french = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("fr") }

        guard !french.isEmpty else {
            return AVSpeechSynthesisVoice(language: "fr-FR")
        }

        return french.max { left, right in
            score(for: left) < score(for: right)
        }
    }

    private static func score(for voice: AVSpeechSynthesisVoice) -> Int {
        var total = 0

        switch voice.quality {
        case .premium:  total += 60
        case .enhanced: total += 40
        default:        total += 10
        }

        if voice.gender == .female { total += 25 }
        if voice.language == "fr-FR" { total += 10 }

        return total
    }

    // MARK: - Passerelle vers le délégué

    /// `AVSpeechSynthesizer` exige un délégué `NSObject`, ce qu'une classe
    /// `@Observable` ne peut pas être. D'où cette petite classe séparée.
    private final class Coordinator: NSObject, AVSpeechSynthesizerDelegate {

        /// Appelée une seule fois, que la phrase se termine ou soit coupée.
        var onFinish: (() -> Void)?

        private func finish() {
            let callback = onFinish
            onFinish = nil
            callback?()
        }

        func speechSynthesizer(
            _ synthesizer: AVSpeechSynthesizer,
            didFinish utterance: AVSpeechUtterance
        ) {
            finish()
        }

        func speechSynthesizer(
            _ synthesizer: AVSpeechSynthesizer,
            didCancel utterance: AVSpeechUtterance
        ) {
            finish()
        }
    }
}
