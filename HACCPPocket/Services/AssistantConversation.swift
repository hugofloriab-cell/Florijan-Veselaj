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

    /// Un relevé à inscrire au registre. La première action de l'assistant
    /// qui écrit au lieu d'ouvrir un écran.
    case recordTemperature(equipmentName: String, celsius: Double, isCompliant: Bool)

    case temperatures
    case cleaning
    case foodSample
    case delivery

    /// Entendu, mais pas rattaché à une action connue.
    case unknown

    var title: String {
        switch self {
        case .openedProduct: return "Produit entamé"
        case .recordTemperature(_, _, let isCompliant):
            return isCompliant ? "Relevé conforme" : "Relevé hors plage"
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
        case .recordTemperature(_, _, let isCompliant):
            return isCompliant ? "thermometer.medium" : "exclamationmark.triangle.fill"
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
        case .recordTemperature: return "Enregistrer le relevé"
        case .temperatures:  return "Ouvrir les températures"
        case .cleaning:      return "Ouvrir le nettoyage"
        case .foodSample:    return "Ouvrir les plats témoins"
        case .delivery:      return "Ouvrir la réception"
        case .unknown:       return "Reformuler"
        }
    }

    /// Le détail reconnu, affiché sous le titre pour qu'on puisse démentir.
    var detail: String? {
        switch self {
        case .openedProduct(let name, let quantity):
            let parts = [name, quantity].filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .recordTemperature(let equipmentName, let celsius, _):
            return "\(equipmentName) · \(AssistantAction.written(celsius)) °C"
        default:
            return nil
        }
    }

    /// « 3 », « −18,5 ». Le séparateur décimal est celui du français.
    static func written(_ celsius: Double) -> String {
        celsius == celsius.rounded()
            ? String(Int(celsius.rounded()))
            : String(format: "%.1f", celsius).replacingOccurrences(of: ".", with: ",")
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
    /// Un relevé qu'on dicte pour l'inscrire au registre.
    case enregistrerTemperature
    /// La demande d'ouvrir l'écran des températures, sans rien y écrire.
    case ouvrirTemperatures
    case nettoyage
    case platTemoin
    case controleReception
    case autre
}

/// Un tour de parole de l'assistant.
///
/// Noter ce qui n'y est pas : aucune date, aucune durée, aucun allergène,
/// et plus aucune quantité. Le modèle ne peut pas en produire puisqu'il n'a
/// nulle part où les mettre.
///
/// La quantité en a été retirée après coup. Le schéma portait un exemple —
/// « par exemple 1 kg » — et le modèle le recopiait : dix kilos de farine
/// devenaient un kilo. C'est `SpokenQuantity` qui la lit maintenant, dans
/// le texte dicté, par du code.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable(description: "Ce que l'assistant répond au cuisinier")
struct SpokenReply {

    @Guide(description: "Ce que l'assistant dit à voix haute. Une seule phrase courte, en français parlé.")
    var spoken: String

    @Guide(description: "L'action dont on parle depuis le début de la conversation. « autre » tant qu'on ne sait pas.")
    var intent: SpokenIntent

    @Guide(description: "Le nom de l'aliment, sans la quantité ni l'emballage. Chaîne vide tant qu'il n'est pas connu.")
    var productName: String

    @Guide(description: "Le nom de l'enceinte citée, recopié exactement depuis la liste des enceintes enregistrées. Chaîne vide si aucune n'est citée.")
    var equipmentName: String

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

    /// La quantité, lue dans ce qui a été dit et jamais produite par le
    /// modèle. Conservée d'un tour à l'autre : « un kilo » arrive souvent
    /// une phrase après « j'entame du sucre ».
    private(set) var quantity: SpokenQuantity = .none

    /// Le nom de l'aliment, retenu de la même façon. Le modèle le répète
    /// normalement à chaque tour ; s'il l'oublie, on ne le perd pas.
    private(set) var productName = ""

    /// Les enceintes réellement enregistrées, fournies par l'écran.
    ///
    /// Elles sont injectées dans les instructions du modèle. Un assistant
    /// qui ignore le parc invente « Frigo 1 » parce que ça sonne juste, et
    /// rattache le relevé à rien.
    private(set) var equipment: [EquipmentBrief] = []

    /// La température lue dans ce qui a été dit, jamais produite par le
    /// modèle — même règle que pour les quantités et les dates.
    private(set) var temperature: Double?

    /// L'enceinte reconnue dans le parc réel.
    private(set) var matchedEquipment: EquipmentBrief?

    /// Vrai quand le tour précédent portait sur un relevé en cours. C'est
    /// ce qui autorise un nombre nu — « trois » — à valoir une température.
    private var recordingTemperature = false

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
        quantity = .none
        productName = ""
        temperature = nil
        matchedEquipment = nil
        recordingTemperature = false
        sessionBox = nil
    }

    /// Oublie ce qui ne valait que pour la demande qui vient d'aboutir.
    ///
    /// Le fil de la conversation, lui, est conservé : on peut enchaîner
    /// « et le congélateur est à moins 19 » sans tout réexpliquer.
    private func forgetCurrentRequest() {
        quantity = .none
        productName = ""
        temperature = nil
        matchedEquipment = nil
        recordingTemperature = false
    }

    /// Donne à l'assistant le parc réel de l'établissement.
    ///
    /// Les instructions du modèle en dépendent : changer la liste oblige à
    /// repartir d'une session neuve, sinon le modèle continuerait de
    /// raisonner sur l'ancien parc.
    func load(equipment list: [EquipmentBrief]) {
        guard list != equipment else { return }
        equipment = list
        sessionBox = nil
    }

    // MARK: - Un tour de parole

    /// Reçoit ce que le cuisinier vient de dire et décide de la suite.
    func send(_ text: String) async -> Reaction {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty else { return .speak("Je n'ai rien entendu.") }

        append(.cook, said)

        // Lue avant tout le reste, et sur la phrase brute. Une quantité
        // trouvée remplace la précédente ; une phrase qui n'en contient pas
        // laisse la dernière en place.
        let heard = SpokenQuantity.parse(said)
        if !heard.isEmpty { quantity = heard }

        // Un nombre nu ne vaut température que si l'assistant vient d'en
        // demander une. Sans cette condition, « frigo 2 » deviendrait deux
        // degrés à la première phrase venue.
        if let degrees = SpokenTemperature.parse(
            said,
            assumingTemperature: recordingTemperature && temperature == nil
        ) {
            temperature = degrees
        }

        // L'enceinte est cherchée dans la phrase brute, en plus du nom que
        // le modèle renverra : le cuisinier dit « le congél », le modèle
        // écrit parfois autre chose, et c'est le parc réel qui tranche.
        if matchedEquipment == nil {
            matchedEquipment = EquipmentMatcher.match(said, in: equipment)
        }

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
                let sentence = Self.openingSentence(for: action)
                // La demande est close : ce qui a été réuni pour elle ne
                // doit pas déborder sur la suivante. Sans cet oubli, un
                // « j'entame du beurre » hériterait de la quantité du
                // sucre, et le registre porterait un chiffre jamais dit.
                forgetCurrentRequest()
                return finish(.act(action, sentence))

            case .no:
                // Ce que le code tenait pour acquis redevient à demander.
                //
                // Dire « non » sert le plus souvent à corriger l'enceinte
                // ou le chiffre ; les garder rendrait la correction
                // impossible, puisqu'ils ne sont relus que lorsqu'ils
                // manquent. Le modèle, lui, garde le fil de la discussion.
                matchedEquipment = nil
                temperature = nil
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
    /// Calculé plutôt que figé, parce que le parc d'enceintes en fait
    /// partie. Un assistant à qui l'on n'a pas dit quels frigos existent
    /// invente « Frigo 1 » — c'est plausible, c'est faux, et le relevé se
    /// retrouve rattaché à rien.
    ///
    /// Trois consignes y comptent plus que les autres. « Une question à la
    /// fois » : en cuisine on répond à une question, pas à trois. « Ne
    /// prononce jamais de nombre » : les quantités et les températures sont
    /// relues dans le texte dicté, et un chiffre venu du modèle serait faux
    /// sans que personne le voie. « N'invente jamais de date » : une durée
    /// de conservation est une obligation réglementaire que l'application
    /// calcule elle-même.
    private var instructions: String {
        """
        Tu es l'assistant vocal du registre d'hygiène d'un restaurant \
        français. Tu t'adresses à un cuisinier en plein service.

        Tu parles, tu ne rédiges pas : une seule phrase courte à chaque fois.

        Ton travail est de reconnaître l'action demandée et de réunir ce qui \
        manque pour l'accomplir.
        - Produit entamé : il te faut le nom de l'aliment. Demande la \
        quantité une seule fois, et passe outre si elle n'est pas donnée.
        - Relevé de température à enregistrer : il te faut l'enceinte et la \
        température. Demande ce qui manque, l'un après l'autre.
        - Nettoyage, plat témoin, contrôle à réception, ouverture de \
        l'écran des températures : aucun détail supplémentaire n'est requis.

        \(equipmentBlock)

        Pose une question à la fois, jamais deux.

        Ne prononce jamais de nombre, ni en chiffres ni en lettres. Dis \
        « quelle température ? », jamais « trois degrés ? ». L'application \
        relit les nombres dans ce qui a été dicté ; un nombre venant de toi \
        serait faux.

        Dès que tu as ce qu'il faut, demande confirmation et mets \
        isReadyToAct à vrai.

        N'invente jamais de date, de durée de conservation ni d'allergène, \
        et n'en demande jamais : l'application les calcule elle-même.

        Si la demande ne correspond à aucune action connue, dis-le \
        simplement et propose les actions possibles.
        """
    }

    /// Le parc réel, écrit pour être lu par le modèle.
    private var equipmentBlock: String {
        guard !equipment.isEmpty else {
            return """
            Aucune enceinte n'est enregistrée dans cet établissement. Si on \
            te demande un relevé de température, dis qu'il faut d'abord \
            créer une enceinte dans l'écran Températures.
            """
        }

        let lines = equipment.map { brief in
            let place = brief.location.isEmpty ? "" : ", \(brief.location)"
            return "- \(brief.name) (\(brief.typeLabel)\(place))"
        }

        return """
        Les enceintes enregistrées dans cet établissement, et elles seules :
        \(lines.joined(separator: "\n"))

        Recopie le nom exactement tel qu'il figure ci-dessus dans \
        equipmentName. N'invente jamais d'enceinte : si celle qu'on te cite \
        n'y est pas, demande laquelle parmi celles de la liste.
        """
    }

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
        let created = LanguageModelSession(instructions: instructions)
        sessionBox = created
        return created
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func interpret(_ reply: SpokenReply) -> Reaction {
        let spoken = reply.spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentence = spoken.isEmpty ? "Je n'ai pas compris." : spoken

        let action = self.action(from: reply)

        guard reply.isReadyToAct, action.isActionable else {
            phase = .awaitingDetail
            return finish(.speak(sentence))
        }

        // Le récapitulatif est écrit ici, pas par le modèle.
        //
        // C'est la phrase sur laquelle le cuisinier dit « oui » : elle doit
        // énoncer exactement ce qui sera ouvert. Laisser le modèle la
        // formuler, c'est accepter qu'il prononce un nombre — et c'est
        // précisément par là que « dix kilos » devenait « un kilo ».
        phase = .awaitingConfirmation(action)
        return finish(.confirm(action, confirmationSentence(for: action)))
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func action(from reply: SpokenReply) -> AssistantAction {
        let heard = reply.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !heard.isEmpty { productName = heard }

        // Le nom d'enceinte que renvoie le modèle est traité comme une
        // proposition, pas comme une vérité : il n'est retenu que s'il
        // correspond à une enceinte réellement enregistrée.
        let named = reply.equipmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !named.isEmpty, let found = EquipmentMatcher.match(named, in: equipment) {
            matchedEquipment = found
        }

        switch reply.intent {
        case .produitEntame:
            // Sans nom, il n'y a rien à ouvrir : on reste en conversation.
            return productName.isEmpty
                ? .unknown
                : .openedProduct(name: productName, quantity: quantity.written)

        case .enregistrerTemperature:
            // On note qu'un relevé est en cours : c'est ce qui autorisera
            // un « trois » tout seul à valoir trois degrés au tour suivant.
            recordingTemperature = true

            // Il manque l'enceinte ou le chiffre : l'assistant demande, et
            // rien n'est proposé à la confirmation tant que les deux ne
            // sont pas là. Un relevé incomplet n'existe pas.
            guard let brief = matchedEquipment, let celsius = temperature else {
                return .unknown
            }

            return .recordTemperature(
                equipmentName: brief.name,
                celsius: celsius,
                isCompliant: brief.accepts(celsius)
            )

        case .ouvrirTemperatures:  return .temperatures
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

    /// Le récapitulatif sur lequel on demande l'accord.
    ///
    /// Écrit ici, en français parlé, à partir de ce que le code a lu : le
    /// nom vient du modèle, la quantité de `SpokenQuantity`. Ce qu'on
    /// entend est donc exactement ce qui sera ouvert.
    private func confirmationSentence(for action: AssistantAction) -> String {
        switch action {
        case .openedProduct(let name, _):
            let what = quantity.isEmpty ? name : "\(quantity.spoken) de \(name)"
            return "\(what). J'ouvre la fiche ?"

        case .recordTemperature(let equipmentName, let celsius, let isCompliant):
            // L'écart est annoncé avant la question, pas après.
            //
            // Un relevé hors plage impose une action corrective ; la
            // personne doit l'apprendre au moment de dire oui, pas en
            // relisant son registre trois semaines plus tard.
            let verdict: String
            if isCompliant {
                verdict = "C'est dans la plage."
            } else if let brief = matchedEquipment {
                verdict = "Attention, c'est hors plage : la consigne est \(brief.spokenRange)."
            } else {
                verdict = "Attention, c'est hors plage."
            }
            return "\(equipmentName), \(Self.spokenDegrees(celsius)). \(verdict) J'enregistre ?"

        case .temperatures: return "Relevé de température. J'ouvre ?"
        case .cleaning:     return "Nettoyage. J'ouvre ?"
        case .foodSample:   return "Plat témoin. J'ouvre ?"
        case .delivery:     return "Contrôle à réception. J'ouvre ?"
        case .unknown:      return "Je n'ai pas compris."
        }
    }

    /// « trois degrés », « moins 18 degrés », « 4 virgule 5 degrés ».
    ///
    /// Le signe se dit en toutes lettres : lu tel quel, le tiret d'un
    /// « −18 » se perd, et le congélateur paraît être à dix-huit degrés.
    private static func spokenDegrees(_ celsius: Double) -> String {
        let written = AssistantAction.written(abs(celsius))
            .replacingOccurrences(of: ",", with: " virgule ")
        let sign = celsius < 0 ? "moins " : ""
        let unit = abs(celsius) <= 1 ? "degré" : "degrés"
        return "\(sign)\(written) \(unit)"
    }

    /// Ce qu'on dit en ouvrant l'écran, une fois l'accord donné.
    private static func openingSentence(for action: AssistantAction) -> String {
        switch action {
        case .openedProduct(let name, _):
            return name.isEmpty ? "J'ouvre la fiche." : "J'ouvre la fiche de \(name)."
        case .recordTemperature: return "C'est noté."
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
