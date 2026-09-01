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
//  QUELLE VOIX EST UTILISÉE — ET POURQUOI CELLE DES RÉGLAGES NE L'ÉTAIT PAS
//  ─────────────────────────────────────────────────────────────────────────
//
//  Première version : l'application notait chaque voix française installée
//  (qualité, genre, variante) et gardait la mieux classée. Erreur de
//  conception. Choisir une voix « objectivement meilleure » écrase le choix
//  fait dans Réglages → Accessibilité → Lire et énoncer → Voix : la personne
//  sélectionne une voix, l'application en impose une autre, et rien n'en
//  informe.
//
//  Règle retenue : par défaut on ne fixe aucune voix. `utterance.voice` reste
//  `nil`, et `AVSpeechSynthesizer` prend la voix par défaut du système —
//  celle des Réglages. L'application ne décide plus à la place de personne.
//
//  Deux exceptions, toutes deux nécessaires :
//
//  • Si la langue par défaut du système n'est pas le français, laisser `nil`
//    ferait lire un texte français avec une voix anglaise : incompréhensible.
//    Dans ce seul cas on retombe sur une voix française installée.
//
//  • Si l'utilisateur choisit explicitement une voix dans l'application
//    (écran « Voix »), c'est cette voix-là, et elle est retenue.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QU'UNE APPLICATION NE PEUT PAS FAIRE, ET QU'IL FAUT DIRE
//  ─────────────────────────────────────────────────────────────────────────
//
//  Le panneau « Voix » des réglages propose aussi les voix de Siri. Elles
//  sont réservées au système : `AVSpeechSynthesisVoice.speechVoices()` ne
//  les renvoie pas, et aucune application tierce ne peut les utiliser. Une
//  voix Siri sélectionnée dans les réglages ne s'entendra donc jamais ici —
//  ce n'est pas un défaut de l'application, c'est une limite d'iOS.
//
//  De même, une voix « améliorée » ou « premium » doit être téléchargée pour
//  exister ; tant que le téléchargement n'est pas terminé, elle n'apparaît
//  nulle part. L'écran « Voix » de l'application liste exactement les voix
//  réellement utilisables, ce qui rend la différence visible au lieu de la
//  laisser deviner.
//

import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class SpeechNarrator {

    // MARK: - Clés de préférences

    private static let voiceKey = "haccp.voice.identifier"
    private static let rateKey = "haccp.voice.rate"

    /// Vitesse de lecture par défaut.
    ///
    /// La valeur d'origine d'iOS est trop rapide pour une consigne qu'on
    /// entend une seule fois, en cuisine, avec du bruit autour. On ralentit
    /// nettement : mieux vaut une phrase de plus que deux relectures.
    ///
    /// Le curseur « Débit vocal » des réglages système ne s'applique qu'à
    /// VoiceOver et à « Lire l'écran » ; il n'est pas lisible par une
    /// application. D'où un réglage propre, exposé dans l'écran « Voix ».
    static let defaultRate: Float = 0.46

    static let minimumRate: Float = 0.34
    static let maximumRate: Float = 0.58

    /// Hauteur de voix, légèrement sous la normale.
    ///
    /// Une voix un peu plus grave est perçue comme plus posée et plus sûre
    /// d'elle. Descendre davantage la rendrait caverneuse.
    private static let pitch: Float = 0.96

    private let synthesizer = AVSpeechSynthesizer()
    private let coordinator = Coordinator()

    private(set) var isSpeaking = false

    // MARK: - Choix de l'utilisateur

    /// Identifiant de la voix choisie dans l'application.
    ///
    /// `nil` — le cas normal — signifie « voix du système », c'est-à-dire
    /// celle des réglages. On ne mémorise une valeur que si quelqu'un a
    /// délibérément forcé une autre voix ici.
    var selectedVoiceIdentifier: String? {
        didSet {
            guard selectedVoiceIdentifier != oldValue else { return }
            let defaults = UserDefaults.standard
            if let identifier = selectedVoiceIdentifier {
                defaults.set(identifier, forKey: Self.voiceKey)
            } else {
                defaults.removeObject(forKey: Self.voiceKey)
            }
            stop()
        }
    }

    /// Vitesse retenue, modifiable depuis l'écran « Voix ».
    var rate: Float {
        didSet {
            guard rate != oldValue else { return }
            UserDefaults.standard.set(rate, forKey: Self.rateKey)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        self.selectedVoiceIdentifier = defaults.string(forKey: Self.voiceKey)
        // `object(forKey:)` sert uniquement à distinguer « jamais réglé » de
        // « réglé à zéro » : `float(forKey:)` renvoie 0 dans les deux cas.
        if defaults.object(forKey: Self.rateKey) != nil {
            self.rate = defaults.float(forKey: Self.rateKey)
        } else {
            self.rate = Self.defaultRate
        }
        synthesizer.delegate = coordinator
    }

    // MARK: - Voix effectivement employée

    /// Valeur sentinelle : « laisse parler la voix par défaut du système ».
    ///
    /// Distincte de `nil`, qui signifie « choisis pour moi la meilleure voix
    /// installée ». Les deux existent parce qu'ils répondent à deux demandes
    /// contraires, formulées à quelques jours d'intervalle : respecter le
    /// réglage d'iOS, et ne pas avoir à choisir soi-même.
    static let systemVoiceIdentifier = "haccp.voice.system"

    /// Toutes les voix françaises réellement utilisables par l'application.
    ///
    /// Triées de la plus naturelle à la plus mécanique.
    var availableFrenchVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("fr") }
            .sorted { score(for: $0) > score(for: $1) }
    }

    /// La voix que l'application retient d'elle-même.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// POURQUOI UN CHOIX AUTOMATIQUE, DE NOUVEAU
    /// ─────────────────────────────────────────────────────────────────────
    ///
    /// Une version précédente classait les voix et imposait la première, en
    /// silence : c'était un défaut, parce que le réglage fait dans iOS était
    /// écrasé sans que rien ne le dise. La correction a été de tout laisser
    /// au système — et le résultat a été jugé, à raison, quelconque.
    ///
    /// Le classement revient donc, mais visible : l'écran « Voix » affiche
    /// quelle voix a été retenue, sa qualité, et permet d'en changer ou de
    /// revenir à celle du système. Choisir pour quelqu'un est acceptable
    /// tant qu'on lui montre ce qu'on a choisi.
    var recommendedVoice: AVSpeechSynthesisVoice? {
        availableFrenchVoices.first
    }

    /// La voix passée au synthétiseur, ou `nil` pour laisser faire le système.
    var effectiveVoice: AVSpeechSynthesisVoice? {
        if selectedVoiceIdentifier == Self.systemVoiceIdentifier { return nil }

        if let identifier = selectedVoiceIdentifier,
           let chosen = AVSpeechSynthesisVoice(identifier: identifier) {
            return chosen
        }

        return recommendedVoice
    }

    /// L'application choisit-elle seule, ou une voix a-t-elle été imposée ?
    var usesRecommendedVoice: Bool { selectedVoiceIdentifier == nil }

    var usesSystemVoice: Bool { selectedVoiceIdentifier == Self.systemVoiceIdentifier }

    /// Nom affichable de la voix employée à cet instant.
    var voiceName: String {
        effectiveVoice?.name ?? "Voix du système"
    }

    /// Qualité affichable de la voix employée.
    var voiceQualityLabel: String? {
        effectiveVoice.map { Self.qualityLabel(for: $0) }
    }

    /// La voix employée est-elle la version compacte d'origine ?
    ///
    /// C'est elle qu'on entend comme « générique, sans intonation ». Quand la
    /// voix vient du système, sa qualité est inconnue : dans le doute on ne
    /// dit rien plutôt que d'afficher un conseil peut-être inutile.
    var usesCompactVoice: Bool {
        guard let voice = effectiveVoice else { return false }
        return voice.quality == .default
    }

    /// Y a-t-il au moins une voix française plus naturelle installée ?
    ///
    /// Réponse « non » = la seule chose utile à faire est un téléchargement,
    /// et l'écran ne doit parler que de ça.
    var hasNaturalFrenchVoice: Bool {
        availableFrenchVoices.contains { $0.quality != .default }
    }

    static func qualityLabel(for voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium:  return "Premium"
        case .enhanced: return "Améliorée"
        default:        return "Compacte"
        }
    }

    /// Note d'une voix : qualité d'abord, puis le genre demandé, puis le
    /// français de France avant les autres variantes.
    ///
    /// L'écart entre deux qualités (30) dépasse volontairement tout le reste :
    /// une voix Premium masculine vaut mieux qu'une compacte féminine, parce
    /// que c'est le naturel qui manque, pas le timbre.
    private func score(for voice: AVSpeechSynthesisVoice) -> Int {
        var total = 0

        switch voice.quality {
        case .premium:  total += 60
        case .enhanced: total += 30
        default:        total += 0
        }

        if voice.gender == .female { total += 8 }
        if voice.language == "fr-FR" { total += 4 }

        return total
    }

    // MARK: - Lecture

    /// Silence entre deux phrases d'un même texte.
    ///
    /// Sans lui, la synthèse enchaîne les phrases sans reprendre son souffle
    /// et tout se fond en un bloc. Un tiers de seconde suffit à redonner de
    /// la ponctuation à l'oreille.
    private static let sentencePause: Duration = .milliseconds(320)

    /// Prononce un texte, phrase par phrase, et ne rend la main qu'à la fin.
    ///
    /// L'attente est ce qui règle le rythme de l'animation : une image reste
    /// affichée tant que son texte n'est pas terminé. Un texte long tient
    /// donc l'écran plus longtemps, ce qui est exactement ce qu'on veut.
    func speak(_ text: String) async {
        let sentences = Self.sentences(in: text)
        guard !sentences.isEmpty else { return }

        prepareAudioSession()

        isSpeaking = true
        defer { isSpeaking = false }

        for (index, sentence) in sentences.enumerated() {
            if Task.isCancelled { return }
            await speakOne(sentence)
            if Task.isCancelled { return }

            if index < sentences.count - 1 {
                try? await Task.sleep(for: Self.sentencePause)
            }
        }
    }

    /// Prononce une phrase et attend qu'elle soit finie.
    private func speakOne(_ sentence: String) async {
        let spoken = Self.spokenForm(sentence)
        guard !spoken.isEmpty else { return }

        stop()

        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = effectiveVoice
        utterance.rate = rate
        utterance.pitchMultiplier = Self.pitch
        utterance.postUtteranceDelay = 0

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

    // MARK: - Découpage en phrases

    /// Découpe un texte en phrases.
    ///
    /// Le découpage se fait sur le texte d'origine, avant toute réécriture :
    /// les abréviations développées plus bas contiennent des points
    /// (« D.L.C. ») qui tromperaient le découpeur et hacheraient la lecture.
    private static func sentences(in text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var result: [String] = []
        trimmed.enumerateSubstrings(
            in: trimmed.startIndex..<trimmed.endIndex,
            options: [.bySentences]
        ) { substring, _, _, _ in
            let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !sentence.isEmpty { result.append(sentence) }
        }

        return result.isEmpty ? [trimmed] : result
    }

    // MARK: - Prononciation

    /// Réécrit ce qui s'écrit court mais se prononce long.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// POURQUOI CE PASSAGE OBLIGÉ
    /// ─────────────────────────────────────────────────────────────────────
    ///
    /// Les textes des modes opératoires sont écrits pour être lus des yeux :
    /// « +3 °C », « DLC », « n° 852/2004 », « 15 min ». Une synthèse vocale
    /// bute sur tout cela — elle dit « degré C », épelle mal les sigles, ou
    /// saute purement et simplement le symbole. En cuisine, une température
    /// mal prononcée n'est pas un détail de confort : c'est la consigne qui
    /// devient fausse.
    ///
    /// Les substitutions sont appliquées dans l'ordre : le signe d'abord
    /// (« +3 » → « plus 3 »), l'unité ensuite (« °C » → « degrés »).
    static func spokenForm(_ text: String) -> String {
        var result = text
        for rule in substitutions {
            result = result.replacingOccurrences(
                of: rule.pattern,
                with: rule.replacement,
                options: .regularExpression
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let substitutions: [(pattern: String, replacement: String)] = [
        // Signes devant un nombre. Le « − » typographique (U+2212) utilisé
        // pour les températures négatives n'est pas prononcé du tout.
        //
        // Groupe capturant plutôt que rétro-référence : une rétro-référence
        // de longueur variable n'est pas garantie par le moteur d'iOS.
        ("(^|[\\s(])\\+(?=\\d)", "$1plus "),
        ("(^|[\\s(])[-\u{2212}](?=\\d)", "$1moins "),

        // Unités. L'ordre compte : « n° » doit être traité avant le degré
        // isolé, sinon « n° 852 » devient « n degrés 852 ».
        ("\\s*°\\s*C\\b", " degrés"),
        ("\\b[nN]\\s*°\\s*", "numéro "),
        ("\\s*°(?![A-Za-z])", " degrés"),
        ("\\s*%", " pour cent"),
        ("(\\d)\\s*h\\b", "$1 heures"),
        ("(\\d)\\s*min\\b", "$1 minutes"),
        ("(\\d)\\s*kg\\b", "$1 kilos"),
        ("m²", "mètres carrés"),

        // Sigles du métier. Sans les points, la synthèse tente de les lire
        // comme des mots : « dlc » devient un borborygme.
        ("\\bDLUO\\b", "D.L.U.O."),
        ("\\bDLC\\b", "D.L.C."),
        ("\\bDDM\\b", "D.D.M."),
        ("\\bHACCP\\b", "H.A.C.C.P."),
        ("\\bPMS\\b", "P.M.S."),
        ("\\bTIAC\\b", "T.I.A.C."),
        ("\\bCE\\b", "C.E."),

        ("\\s{2,}", " ")
    ]

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
