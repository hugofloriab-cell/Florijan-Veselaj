//
//  AssistantConversation.swift
//  HACCPPocket
//
//  Une conversation, pas une commande vocale.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUI CHANGE PAR RAPPORT À L'ÉTAPE PRÉCÉDENTE
//  ─────────────────────────────────────────────────────────────────────────
//
//  Avant, chaque phrase était comprise isolément : on parlait, l'application
//  devinait, et tout recommençait à zéro au coup suivant. Ce n'était pas un
//  assistant, c'était un bouton qu'on actionnait avec la voix.
//
//  Ici la session de langage est conservée d'un tour à l'autre. L'assistant
//  se souvient de ce qui a été dit, peut donc poser une question quand il
//  manque un renseignement, et comprendre une réponse qui ne tient qu'en un
//  mot — « un kilo » n'a de sens que si l'on se souvient qu'on parlait de
//  sucre.
//
//  ─────────────────────────────────────────────────────────────────────────
//  LA LIMITE QU'ON NE FRANCHIT TOUJOURS PAS
//  ─────────────────────────────────────────────────────────────────────────
//
//  Aucune date, aucune durée de conservation, aucun allergène ne sort d'ici.
//  Ce sont des obligations réglementaires — arrêté du 21 décembre 2009,
//  règlement 852/2004 — et un registre rempli d'après une phrase mal
//  entendue serait un faux. La structure que le modèle remplit ne comporte
//  aucun champ de date : c'est ce qui l'en empêche réellement, bien plus
//  sûrement qu'une consigne dans l'invite.
//
//  Et rien n'est écrit sans un accord explicite. L'assistant récapitule,
//  demande, et attend. Un « oui » à la voix ou un doigt sur le bouton :
//  jamais le simple fait d'avoir parlé.
//

import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Ce que l'écran peut faire de la demande

/// L'intention reconnue, exprimée sans rien qui dépende d'iOS 26.
///
/// Le reste de l'application manipule ce type-là : les écrans n'ont ainsi
/// aucune raison de savoir qu'un modèle de langage existe.
enum AssistantAction: Equatable {

    /// Le cas principal : un produit qu'on ouvre.
    case openedProduct(name: String, quantity: String)

    case temperatures
    case cleaning
    case foodSample
    case delivery

    /// Entendu, mais pas rattaché à une action connue.
    case unknown

    var title: String {
        switch self {
        case .openedProduct: return "Produit entamé"
        case .temperatures:  return "Relevé de température"
        case .cleaning:      return "Nettoyage"
        case .foodSample:    return "Plat témoin"
        case .delivery:      return "Contrôle à réception"
        case .unknown:       return "Demande non reconnue"
        }
    }

    var systemImage: String {
        switch self {
        case .openedProduct: return "shippingbox"
        case .temperatures:  return "thermometer.medium"
        case .cleaning:      return "sparkles"
        case .foodSample:    return "takeoutbag.and.cup.and.straw"
        case .delivery:      return "shippingbox.and.arrow.backward"
        case .unknown:       return "questionmark.circle"
        }
    }

    /// Ce qui est écrit sur le bouton. Un verbe, et ce qui va s'ouvrir.
    var actionLabel: String {
        switch self {
        case .openedProduct: return "Ouvrir la fiche produit"
        case .temperatures:  return "Ouvrir les températures"
        case .cleaning:      return "Ouvrir le nettoyage"
        case .foodSample:    return "Ouvrir les plats témoins"
        case .delivery:      return "Ouvrir la réception"
        case .unknown:       return "Reformuler"
        }
    }

    /// Le détail reconnu, affiché sous le titre pour qu'on puisse démentir.
    var detail: String? {
        guard case .openedProduct(let name, let quantity) = self else { return nil }
        let parts = [name, quantity].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var isActionable: Bool { self != .unknown }
}

// MARK: - Le type que le modèle remplit

#if canImport(FoundationModels)

/// L'action demandée, telle que le modèle a le droit de la nommer.
///
/// Les cas sont en français : le modèle voit les noms du schéma, et une
/// invite française répond mieux à un vocabulaire français.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable
enum SpokenIntent {
    case produitEntame
    case releveDeTemperature
    case nettoyage
    case platTemoin
    case controleReception
    case autre
}

/// Un tour de parole de l'assistant.
///
/// Noter ce qui n'y est pas : aucune date, aucune durée, aucun allergène.
/// Le modèle ne peut pas en produire puisqu'il n'a nulle part où les mettre.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable(description: "Ce que l'assistant répond au cuisinier")
struct SpokenReply {

    @Guide(description: "Ce que l'assistant dit à voix haute. Une seule phrase courte, en français parlé.")
    var spoken: String

    @Guide(description: "L'action dont on parle depuis le début de la conversation. « autre » tant qu'on ne sait pas.")
    var intent: SpokenIntent

    @Guide(description: "Le nom de l'aliment, sans la quantité ni l'emballage. Chaîne vide tant qu'il n'est pas connu.")
    var productName: String

    @Guide(description: "La quantité ou le conditionnement, par exemple « 1 kg ». Chaîne vide si elle n'a pas été dite.")
    var quantity: String

    @Guide(description: "Vrai seulement quand il ne manque plus rien et que la phrase dite ci-dessus est une demande de confirmation.")
    var isReadyToAct: Bool
}

#endif

// MARK: - La conversation

@MainActor
@Observable
final class AssistantConversation {

    /// Une réplique, pour l'afficher à l'écran.
    struct Turn: Identifiable, Equatable {
        enum Speaker: Equatable { case cook, assistant }
        let id = UUID()
        let speaker: Speaker
        let text: String
    }

    /// Où en est l'échange. Sert à l'affichage, pas à décider.
    enum Phase: Equatable {
        case idle
        case thinking
        /// L'assistant a posé une question et attend la réponse.
        case awaitingDetail
        /// Tout est réuni : on attend un oui ou un non.
        case awaitingConfirmation(AssistantAction)
        case failed(String)
    }

    /// Ce que l'écran doit faire du tour qui vient de se jouer.
    ///
    /// C'est volontairement l'appelant qui orchestre : parler, rouvrir le
    /// micro et naviguer sont des gestes d'interface, pas de compréhension.
    enum Reaction: Equatable {
        /// Dire la phrase, puis rouvrir le micro.
        case speak(String)
        /// Dire la phrase — un récapitulatif — puis rouvrir le micro pour
        /// attendre l'accord.
        case confirm(AssistantAction, String)
        /// L'accord est donné : dire la phrase, puis ouvrir l'écran.
        case act(AssistantAction, String)
        /// Fin de l'échange : dire la phrase et refermer le micro.
        case stop(String)
        /// Rien ne s'est passé comme prévu, et on dit pourquoi.
        case failed(String)
    }

    private(set) var turns: [Turn] = []
    private(set) var phase: Phase = .idle

    /// La session de langage, conservée entre les tours.
    ///
    /// Rangée en `AnyObject` parce que son type n'existe qu'à partir d'iOS
    /// 26 : une propriété stockée ne peut pas porter d'annotation de
    /// disponibilité, mais une conversion le peut.
    private var sessionBox: AnyObject?

    /// Au-delà, on oublie le début. Le modèle embarqué dispose d'environ
    /// quatre mille jetons de contexte ; une conversation de cuisine n'a
    /// jamais besoin d'aller si loin, et tronquer vaut mieux que planter.
    private static let maximumTurns = 24

    // MARK: - Cycle de vie

    func reset() {
        turns = []
        phase = .idle
        sessionBox = nil
    }

    // MARK: - Un tour de parole

    /// Reçoit ce que le cuisinier vient de dire et décide de la suite.
    func send(_ text: String) async -> Reaction {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty else { return .speak("Je n'ai rien entendu.") }

        append(.cook, said)

        // Trois raccourcis traités dans le code, jamais confiés au modèle.
        //
        // Un « oui » doit valoir accord de façon absolument prévisible : si
        // un modèle devait l'interpréter, le même mot pourrait un jour ne
        // plus déclencher l'enregistrement, ou pire, le déclencher à tort.
        if Self.isStopWord(said) {
            phase = .idle
            return finish(.stop("Très bien. À tout à l'heure."))
        }

        if case .awaitingConfirmation(let action) = phase {
            switch Self.agreement(in: said) {
            case .yes:
                phase = .idle
                return finish(.act(action, Self.openingSentence(for: action)))
            case .no:
                // On ne repart pas de zéro : le modèle garde le fil et
                // demandera ce qu'il faut corriger.
                phase = .thinking
            case .unclear:
                phase = .thinking
            }
        }

        guard IntelligenceAvailability.current.isReady else {
            let reason = IntelligenceAvailability.current.summary
            phase = .failed(reason)
            return .failed(reason)
        }

        phase = .thinking

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            return await respond(to: said)
        }
        #endif

        let reason = IntelligenceAvailability.needsNewerSystem.summary
        phase = .failed(reason)
        return .failed(reason)
    }

    // MARK: - Le modèle

    #if canImport(FoundationModels)

    /// Ce qu'on dit au modèle avant toute chose.
    ///
    /// Deux consignes y comptent plus que les autres. « Une question à la
    /// fois » : en cuisine on répond à une question, pas à trois. Et « ne
    /// demande jamais de date » — non par excès de prudence, mais parce
    /// qu'une date dictée puis mal entendue produirait un registre faux,
    /// alors que l'application sait la calculer sans se tromper.
    private static let instructions = """
    Tu es l'assistant vocal du registre d'hygiène d'un restaurant français. \
    Tu t'adresses à un cuisinier en plein service.

    Tu parles, tu ne rédiges pas : une seule phrase courte à chaque fois.

    Ton travail est de reconnaître l'action demandée et de réunir ce qui \
    manque pour l'ouvrir.
    - Pour un produit entamé, il te faut le nom de l'aliment. Si tu ne l'as \
    pas, demande-le. Demande la quantité une seule fois, et passe outre si \
    elle n'est pas donnée.
    - Pour un relevé de température, un nettoyage, un plat témoin ou un \
    contrôle à réception, tu n'as besoin d'aucun détail supplémentaire.

    Pose une question à la fois, jamais deux.

    Dès que tu as ce qu'il faut, récapitule en une phrase et demande \
    confirmation, puis mets isReadyToAct à vrai. Exemple : « Un kilo de \
    sucre en poudre, j'ouvre la fiche ? »

    N'invente jamais de date, de durée de conservation ni d'allergène, et \
    n'en demande jamais : l'application les calcule elle-même.

    Si la demande ne correspond à aucune action connue, dis-le simplement \
    et propose les actions possibles.
    """

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func respond(to said: String) async -> Reaction {
        do {
            return try await ask(said, retryingOnOverflow: true)
        } catch {
            // Le message du système plutôt qu'un « erreur » : un dépassement
            // de contexte et un refus de garde-fou n'appellent pas la même
            // réaction, et seul le texte les distingue.
            let reason = error.localizedDescription
            phase = .failed(reason)
            return .failed(reason)
        }
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func ask(_ said: String, retryingOnOverflow: Bool) async throws -> Reaction {
        let session = currentSession()

        do {
            let response = try await session.respond(to: said, generating: SpokenReply.self)
            return interpret(response.content)
        } catch {
            // Une conversation trop longue finit par dépasser le contexte.
            // On repart d'une session neuve plutôt que d'abandonner : le
            // cuisinier perd le fil, pas sa demande.
            guard retryingOnOverflow else { throw error }
            sessionBox = nil
            return try await ask(said, retryingOnOverflow: false)
        }
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func currentSession() -> LanguageModelSession {
        if let existing = sessionBox as? LanguageModelSession { return existing }
        let created = LanguageModelSession(instructions: Self.instructions)
        sessionBox = created
        return created
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func interpret(_ reply: SpokenReply) -> Reaction {
        let spoken = reply.spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentence = spoken.isEmpty ? "Je n'ai pas compris." : spoken

        let action = Self.action(from: reply)

        guard reply.isReadyToAct, action.isActionable else {
            phase = .awaitingDetail
            return finish(.speak(sentence))
        }

        phase = .awaitingConfirmation(action)
        return finish(.confirm(action, sentence))
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private static func action(from reply: SpokenReply) -> AssistantAction {
        let name = reply.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        let quantity = reply.quantity.trimmingCharacters(in: .whitespacesAndNewlines)

        switch reply.intent {
        case .produitEntame:
            // Sans nom, il n'y a rien à ouvrir : on reste en conversation.
            return name.isEmpty ? .unknown : .openedProduct(name: name, quantity: quantity)
        case .releveDeTemperature: return .temperatures
        case .nettoyage:           return .cleaning
        case .platTemoin:          return .foodSample
        case .controleReception:   return .delivery
        case .autre:               return .unknown
        }
    }

    #endif

    // MARK: - Les mots qu'on reconnaît sans modèle

    enum Agreement { case yes, no, unclear }

    /// Un accord, un refus, ou ni l'un ni l'autre.
    ///
    /// Volontairement déterministe. C'est le mot qui déclenche une écriture
    /// au registre : il doit produire le même effet aujourd'hui et dans six
    /// mois, sans dépendre de l'humeur d'un modèle.
    static func agreement(in text: String) -> Agreement {
        let words = normalizedWords(of: text)
        guard !words.isEmpty else { return .unclear }

        let no: Set<String> = [
            "non", "nan", "pas", "annule", "annuler", "attends", "attend",
            "erreur", "faux", "corrige", "plutot"
        ]
        // Le refus prime : « non, pas celui-là » contient aussi « la ».
        if !no.isDisjoint(with: words) { return .no }

        let yes: Set<String> = [
            "oui", "ouais", "ouaip", "si", "exact", "exactement", "voila",
            "parfait", "ok", "okay", "daccord", "accord", "confirme",
            "confirmer", "vasy", "valide", "valider", "cest", "ca"
        ]
        // « c'est ça » devient « cest ca » : les deux doivent être présents
        // pour valoir accord, sinon « ça » seul confirmerait n'importe quoi.
        if words.contains("cest"), words.contains("ca") { return .yes }

        let strong = yes.subtracting(["cest", "ca", "si"])
        if !strong.isDisjoint(with: words) { return .yes }

        return .unclear
    }

    /// Les mots qui ferment la conversation.
    static func isStopWord(_ text: String) -> Bool {
        let words = normalizedWords(of: text)
        let stop: Set<String> = ["stop", "arrete", "arreter", "laisse", "ferme", "fermer", "quitte"]
        return !stop.isDisjoint(with: words)
    }

    /// Minuscules, sans accents, sans ponctuation, découpé en mots.
    ///
    /// La dictée écrit « d'accord » avec une apostrophe et « ça » avec une
    /// cédille ; comparer sans normaliser reviendrait à ne reconnaître que
    /// la moitié des accords.
    private static func normalizedWords(of text: String) -> Set<String> {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        let pieces = folded.split { !$0.isLetter }
        return Set(pieces.map(String.init))
    }

    /// Ce qu'on dit en ouvrant l'écran, une fois l'accord donné.
    private static func openingSentence(for action: AssistantAction) -> String {
        switch action {
        case .openedProduct(let name, _):
            return name.isEmpty ? "J'ouvre la fiche." : "J'ouvre la fiche de \(name)."
        case .temperatures: return "J'ouvre les températures."
        case .cleaning:     return "J'ouvre le nettoyage."
        case .foodSample:   return "J'ouvre les plats témoins."
        case .delivery:     return "J'ouvre la réception."
        case .unknown:      return "Je n'ai pas compris."
        }
    }

    // MARK: - Le fil affiché

    private func append(_ speaker: Turn.Speaker, _ text: String) {
        turns.append(Turn(speaker: speaker, text: text))
        if turns.count > Self.maximumTurns {
            turns.removeFirst(turns.count - Self.maximumTurns)
        }
    }

    /// Inscrit la réplique de l'assistant au fil, et rend la réaction telle
    /// quelle. Passer par ici garantit qu'aucune phrase dite ne manque à
    /// l'écran — on doit pouvoir relire ce qu'on a entendu de travers.
    private func finish(_ reaction: Reaction) -> Reaction {
        switch reaction {
        case .speak(let text), .stop(let text):
            append(.assistant, text)
        case .confirm(_, let text), .act(_, let text):
            append(.assistant, text)
        case .failed:
            break
        }
        return reaction
    }
}
