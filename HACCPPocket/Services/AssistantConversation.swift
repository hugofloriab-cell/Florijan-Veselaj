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

    /// Un contrôle à réception tiré d'une photo du bon de livraison.
    case recordDelivery(reading: DeliveryNoteReader.Reading, photo: Data, operatorName: String)

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
        case .recordDelivery: return "Contrôle à réception"
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
        case .recordDelivery: return "shippingbox.and.arrow.backward"
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
        case .recordDelivery: return "Enregistrer le contrôle"
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
        case .recordDelivery(let reading, _, let operatorName):
            let parts = [reading.summary, operatorName].filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
    /// « Les températures d'aujourd'hui », « y a-t-il eu des écarts ».
    case recapTemperatures
    case nettoyage
    case platTemoin
    case controleReception
    case autre
}

/// Ce que le modèle a compris de la dernière phrase.
///
/// Deux champs, et c'est tout. Ce schéma en comptait cinq, dont un booléen
/// « j'ai tout ce qu'il faut » et une phrase à prononcer. C'était trop pour
/// un modèle embarqué, et c'est ce qui faisait tourner l'assistant en rond :
/// quand il répondait à tort qu'il lui manquait quelque chose, personne ne
/// le contredisait, et la même question revenait.
///
/// Désormais le modèle classe, et le code décide. Reconnaître une action
/// parmi sept et repérer un nom d'aliment, un modèle embarqué le fait bien.
/// Tenir une conversation et juger de sa propre complétude, non.
///
/// Noter ce qui n'y est toujours pas : ni date, ni durée, ni allergène, ni
/// quantité, ni température. Tout ce qui est chiffré est lu dans le texte
/// dicté, par du code.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable(description: "Ce que demande un cuisinier à son registre d'hygiène")
struct SpokenReply {

    @Guide(description: "L'action demandée. enregistrerTemperature pour dicter un relevé, recapTemperatures pour consulter ceux de la journée, ouvrirTemperatures pour ouvrir l'écran. « autre » si rien ne correspond.")
    var intent: SpokenIntent

    @Guide(description: "Le nom de l'aliment cité, sans la quantité ni l'emballage. Chaîne vide si aucun aliment n'est cité.")
    var productName: String
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
        /// Le tableau affiché sous la réplique, quand il y en a un.
        var report: AssistantReport? = nil
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
        /// Montrer un tableau, en n'en disant que la conclusion.
        case show(AssistantReport)
        /// Demander une photo, et l'attendre. L'appareil s'ouvre dans le fil.
        case capture(String)
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

    /// Le relevé du jour, préparé par l'écran à partir du registre.
    ///
    /// Calculé au moment d'ouvrir l'assistant, pas ici : les objets
    /// SwiftData ne traversent pas les frontières de concurrence, et un
    /// tableau déjà mis en forme les traverse sans difficulté.
    private(set) var temperatureReport: AssistantReport?

    /// Le nom de la personne qui contrôle, repris des réglages.
    ///
    /// Un contrôle à réception sans nom d'opérateur n'est pas un contrôle :
    /// le règlement 852/2004 veut savoir qui a vérifié. Quand les réglages
    /// n'en portent pas, l'assistant le demande plutôt que d'inscrire un
    /// registre anonyme.
    private(set) var operatorName = ""

    /// La livraison lue, en attente du nom de qui la contrôle.
    private struct PendingDelivery {
        var reading: DeliveryNoteReader.Reading
        var photo: Data
    }

    private var pendingDelivery: PendingDelivery?

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

    /// Ce que l'application vient de demander, et attend.
    ///
    /// C'est la pièce qui manquait. Sans elle, une réponse à une question
    /// repartait vers le modèle comme s'il s'agissait d'une demande neuve :
    /// « du sucre » n'étant pas une demande, il reclassait en « autre », et
    /// la même question revenait indéfiniment. Quand une question est en
    /// attente, le code prend la réponse lui-même, sans modèle.
    private enum PendingQuestion: Equatable {
        case productName
        case equipment
        case temperature
        /// On attend une photo du bon de livraison.
        case photo
        /// On attend le nom de la personne qui contrôle.
        case operatorName
        /// On attend un oui ou un non sur une proposition.
        case confirmation
        /// On ne sait même pas de quoi il s'agit.
        case intent

        /// Les questions dont la réponse se lit dans le texte, sans modèle.
        ///
        /// Les deux autres en ont besoin : juger qu'une phrase corrige une
        /// proposition, ou reconnaître une demande, demande de classer.
        var isAnsweredByCode: Bool {
            switch self {
            case .productName, .equipment, .temperature, .operatorName: return true
            // Une photo n'est pas du texte, et parler pendant qu'on en
            // attend une est une demande neuve : au modèle de trancher.
            case .photo, .confirmation, .intent: return false
            }
        }
    }

    private var pending: PendingQuestion?

    /// Combien de fois la même question a été posée.
    ///
    /// Au troisième essai on cesse de demander et on propose une sortie :
    /// une fiche vide, ou l'écran à remplir à la main. Insister davantage
    /// ne rend service à personne.
    private var attempts = 0

    /// La dernière phrase, telle que dite. Sert à en extraire un nom quand
    /// le modèle n'en trouve pas.
    private var lastUtterance = ""

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
        pending = nil
        attempts = 0
        lastUtterance = ""
        pendingDelivery = nil
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
        pending = nil
        attempts = 0
    }

    /// Donne à l'assistant le parc réel de l'établissement.
    ///
    /// Les instructions du modèle en dépendent : changer la liste oblige à
    /// repartir d'une session neuve, sinon le modèle continuerait de
    /// raisonner sur l'ancien parc.
    /// L'étiquette est `checkedBy` et non `operator` : ce dernier est un
    /// mot-clé Swift, et le compilateur y lit une déclaration d'opérateur.
    func load(
        equipment list: [EquipmentBrief],
        temperatures: AssistantReport? = nil,
        checkedBy name: String = ""
    ) {
        temperatureReport = temperatures
        operatorName = name.trimmingCharacters(in: .whitespacesAndNewlines)
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
        lastUtterance = said

        // L'état d'avant, pour savoir ensuite si cette phrase a appris
        // quelque chose. C'est ce qui distingue une correction d'un bruit.
        let previousQuantity = quantity
        let previousTemperature = temperature
        let previousEquipment = matchedEquipment

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
                pending = nil
                attempts = 0
                phase = .thinking

            case .unclear:
                // Ni oui ni non. Deux cas, et il faut les séparer.
                //
                // Ou bien la phrase corrige quelque chose — « deux kilos »,
                // « le congélateur » — et il faut la traiter. Ou bien c'est
                // un bruit de cuisine mal transcrit, et la renvoyer au
                // modèle lui ferait reclasser la même intention : on
                // reproposerait mot pour mot la même phrase, indéfiniment.
                //
                // C'est exactement ce qui se produisait.
                let corrected = quantity != previousQuantity
                    || temperature != previousTemperature
                    || matchedEquipment != previousEquipment
                    || correctsProductName(in: said, for: action)

                guard corrected else { return askToConfirm(action) }

                pending = nil
                attempts = 0
                phase = .thinking
            }
        }

        // Une question est en attente : cette phrase en est la réponse.
        //
        // On ne repasse pas par le modèle. Il classerait « du sucre » comme
        // une demande incompréhensible, alors que le code sait parfaitement
        // qu'il vient de demander un nom de produit.
        if let pending, pending.isAnsweredByCode {
            return answer(pending)
        }

        guard IntelligenceAvailability.current.isReady else {
            let reason = IntelligenceAvailability.current.summary
            phase = .failed(reason)
            return .failed(reason)
        }

        phase = .thinking

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            // L'aiguillage par mots-clés d'abord.
            //
            // « Montre-moi les températures » ne laisse aucune place au
            // doute, et le modèle s'y trompait. Trois mots suffisent à
            // décider : inutile de déranger un modèle, qui met un instant
            // à répondre et peut se tromper. Il garde tout le reste.
            if let guessed = SpokenIntentGuess.intent(in: said) {
                if guessed == .produitEntame, productName.isEmpty {
                    productName = SpokenProduct.name(in: said)
                }
                return decide(guessed)
            }

            return await respond(to: said)
        }
        #endif

        let reason = IntelligenceAvailability.needsNewerSystem.summary
        phase = .failed(reason)
        return .failed(reason)
    }

    // MARK: - Le modèle

    #if canImport(FoundationModels)

    /// Ce qu'on demande au modèle — et plus rien d'autre.
    ///
    /// Ces instructions faisaient quarante lignes et contenaient la liste
    /// des enceintes. Deux conséquences, vues à l'usage : le modèle
    /// cherchait une enceinte pour un sac de sucre, et il suivait d'autant
    /// moins bien les consignes qu'elles étaient nombreuses. Un modèle
    /// embarqué dispose d'environ quatre mille jetons ; les dépenser en
    /// consignes, c'est les retirer à la compréhension.
    ///
    /// Il ne reste que la tâche de classement. Les questions, les
    /// récapitulatifs et le choix du moment d'agir sont écrits dans le
    /// code, qui sait exactement ce qui manque.
    private static let instructions = """
    Tu classes ce que dit un cuisinier français à son registre d'hygiène.

    Donne l'action demandée, et le nom de l'aliment quand il y en a un.

    Tu ne tiens pas la conversation et tu ne poses pas de question : \
    l'application s'en charge. Tu ne fais que classer la dernière phrase.
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
            // modèle perd le fil, pas la demande — celle-ci est dans le code.
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
        // Le nom vient du modèle quand il en trouve un, du texte sinon.
        //
        // Les deux chemins comptent : le modèle lit mieux une phrase
        // complexe, le code ne rate jamais un « du sucre ».
        let heard = reply.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !heard.isEmpty {
            productName = heard
        } else if productName.isEmpty {
            productName = SpokenProduct.name(in: lastUtterance)
        }

        return decide(reply.intent)
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func decide(_ intent: SpokenIntent) -> Reaction {
        switch intent {
        case .produitEntame:          return proposeOpenedProduct()
        case .enregistrerTemperature: return proposeTemperatureReading()
        case .ouvrirTemperatures:     return propose(.temperatures)
        case .recapTemperatures:      return showTemperatures()
        case .nettoyage:              return propose(.cleaning)
        case .platTemoin:             return propose(.foodSample)
        case .controleReception:      return askForPhoto()
        case .autre:                  return offerTheMenu()
        }
    }

    #endif

    // MARK: - Les questions, posées par le code

    /// Propose une action et attend l'accord.
    private func propose(_ action: AssistantAction) -> Reaction {
        pending = nil
        attempts = 0
        phase = .awaitingConfirmation(action)
        return finish(.confirm(action, confirmationSentence(for: action)))
    }

    /// La phrase qu'on vient de recevoir répond à la question posée.
    ///
    /// Tout a déjà été relu au début du tour — quantité, température,
    /// enceinte. Il ne reste qu'à voir si ce qui manquait est arrivé.
    private func answer(_ question: PendingQuestion) -> Reaction {
        switch question {
        case .productName:
            let found = SpokenProduct.name(in: lastUtterance)
            if !found.isEmpty { productName = found }
            return proposeOpenedProduct()

        case .equipment, .temperature:
            return proposeTemperatureReading()

        case .operatorName:
            let name = Self.personName(in: lastUtterance)
            if !name.isEmpty { operatorName = name }
            return proposeDelivery()

        case .photo, .confirmation, .intent:
            // Jamais atteint : `isAnsweredByCode` les exclut du raccourci.
            // Le cas existe pour que l'ajout d'une question future ne passe
            // pas silencieusement par ici.
            return offerTheMenu()
        }
    }

    private func proposeOpenedProduct() -> Reaction {
        guard !productName.isEmpty else { return askForProductName() }
        return propose(.openedProduct(name: productName, quantity: quantity.written))
    }

    private func proposeTemperatureReading() -> Reaction {
        // Un relevé est en cours : c'est ce qui autorisera un « trois »
        // tout seul à valoir trois degrés au tour suivant.
        recordingTemperature = true

        guard !equipment.isEmpty else {
            pending = nil
            attempts = 0
            phase = .idle
            return finish(.stop(
                "Aucune enceinte n'est enregistrée. Ajoutez-en une dans l'écran Températures."
            ))
        }

        guard let brief = matchedEquipment else { return askForEquipment() }
        guard let celsius = temperature else { return askForTemperature() }

        return propose(.recordTemperature(
            equipmentName: brief.name,
            celsius: celsius,
            isCompliant: brief.accepts(celsius)
        ))
    }

    // MARK: - Demander, deux fois au plus

    /// Compte les tentatives sur une même question.
    ///
    /// Au troisième essai on cesse de demander. Reposer indéfiniment la
    /// même question est ce qui a rendu l'assistant pénible ; mieux vaut
    /// ouvrir l'écran et laisser faire à la main.
    private func attempt(_ question: PendingQuestion) -> Int {
        attempts = (pending == question) ? attempts + 1 : 1
        pending = question
        return attempts
    }

    private func askForProductName() -> Reaction {
        phase = .awaitingDetail
        switch attempt(.productName) {
        case 1:
            return finish(.speak("Quel produit ?"))
        case 2:
            return finish(.speak("Dites seulement le nom du produit, par exemple : sucre."))
        default:
            // On renonce à comprendre, mais pas à rendre service : la fiche
            // s'ouvre vide, et le nom se tape en deux secondes.
            pending = nil
            attempts = 0
            return propose(.openedProduct(name: "", quantity: quantity.written))
        }
    }

    private func askForEquipment() -> Reaction {
        phase = .awaitingDetail
        switch attempt(.equipment) {
        case 1:
            return finish(.speak("Quelle enceinte ?"))
        case 2:
            // Les noms sont énoncés : on ne devine pas ce qu'on n'a jamais
            // entendu, et le parc de chaque cuisine lui est propre.
            let names = equipment.prefix(4).map(\.name).joined(separator: ", ")
            return finish(.speak("Laquelle : \(names) ?"))
        default:
            pending = nil
            attempts = 0
            return propose(.temperatures)
        }
    }

    private func askForTemperature() -> Reaction {
        phase = .awaitingDetail
        switch attempt(.temperature) {
        case 1:
            return finish(.speak("Quelle température ?"))
        case 2:
            return finish(.speak("Dites le chiffre suivi du mot degrés."))
        default:
            pending = nil
            attempts = 0
            return propose(.temperatures)
        }
    }

    /// Relance l'accord sans jamais répéter la proposition.
    ///
    /// Le récapitulatif reste affiché à l'écran et le bouton aussi : il n'y
    /// a aucune raison de le redire. On demande seulement la décision, puis
    /// on se tait. Un assistant qui répète est pire qu'un assistant muet.
    private func askToConfirm(_ action: AssistantAction) -> Reaction {
        let count = attempt(.confirmation)
        // La carte de confirmation doit rester visible : on ne repasse pas
        // en « question en cours », qui la ferait disparaître.
        phase = .awaitingConfirmation(action)

        switch count {
        case 1:
            return finish(.speak("C'est oui ou non ?"))
        case 2:
            return finish(.speak("Dites oui pour confirmer, ou touchez le bouton à l'écran."))
        default:
            // On cesse de relancer. La proposition reste à l'écran, le
            // doigt fera le reste.
            pending = nil
            attempts = 0
            return finish(.stop("Je vous laisse décider."))
        }
    }

    /// La phrase propose-t-elle un autre produit que celui annoncé ?
    ///
    /// Sert à reconnaître une correction dite sans « non » : « du beurre »
    /// lancé par-dessus une proposition sur le sucre.
    private func correctsProductName(in said: String, for action: AssistantAction) -> Bool {
        guard case .openedProduct(let name, _) = action else { return false }
        let found = SpokenProduct.name(in: said)
        guard !found.isEmpty else { return false }
        return found.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
    }

    /// Montre le relevé du jour, sans rien demander ni rien écrire.
    ///
    /// Aucune confirmation : lire n'engage à rien. C'est la différence de
    /// nature entre montrer et agir, et elle se voit à l'usage — on ne dit
    /// pas « oui » pour consulter un tableau.
    private func showTemperatures() -> Reaction {
        pending = nil
        attempts = 0
        phase = .idle

        guard let report = temperatureReport else {
            return finish(.speak("Je n'ai pas encore le relevé du jour."))
        }
        return finish(.show(report))
    }

    /// Demande la photo du bon de livraison.
    ///
    /// Le contrôle à réception se saisissait à la main : fournisseur,
    /// produit, lot, date, tapés sur une tablette pendant qu'un livreur
    /// attend. C'est le travail que personne n'a le temps de faire, et qui
    /// manque ensuite au registre le jour d'un contrôle. Le bon porte déjà
    /// tout : il suffit de le photographier.
    private func askForPhoto(_ reason: String? = nil) -> Reaction {
        phase = .awaitingDetail

        switch attempt(.photo) {
        case 1:
            return finish(.capture(reason ?? "Prenez le bon de livraison en photo."))
        case 2:
            return finish(.capture(reason ?? "Cadrez le bon bien à plat, l'en-tête visible."))
        default:
            // Deux lectures manquées : la photo n'y arrivera pas, et
            // insister ferait perdre plus de temps que la saisie.
            pending = nil
            attempts = 0
            return propose(.delivery)
        }
    }

    /// Lit la photo et propose le contrôle qui en découle.
    ///
    /// La lecture est faite par `DateOCRService`, qui servait déjà aux
    /// étiquettes : Vision, hors ligne, rien ne sort de l'appareil.
    func receivePhoto(_ data: Data) async -> Reaction {
        append(.cook, "Photo du bon de livraison.")
        phase = .thinking

        guard let scan = try? await DateOCRService.scan(imageData: data) else {
            return askForPhoto("La lecture a échoué. Reprenez la photo.")
        }

        let reading = DeliveryNoteReader.read(scan)

        guard !reading.isEmpty else {
            return askForPhoto("Je n'ai rien pu lire. Reprenez-la de plus près, bien à plat.")
        }

        // Tout ce qui a été lu est montré, sans qu'on ait à le demander.
        //
        // La version précédente n'annonçait que le fournisseur, et demander
        // « donne-moi plus de détails » se heurtait à la garde du oui/non.
        // Un tableau affiché d'office règle les deux : on vérifie d'un coup
        // d'œil, et il n'y a plus de question à poser.
        append(.assistant, "Voilà ce que j'ai lu sur le bon.", report: AssistantReport(
            title: "Bon de livraison",
            rows: DeliveryNoteReader.rows(for: reading),
            spoken: "",
            note: "Vérifiez avant de valider : ce qui est lu de travers s'inscrit au registre."
        ))

        pendingDelivery = PendingDelivery(reading: reading, photo: data)
        pending = nil
        attempts = 0

        return proposeDelivery()
    }

    /// Propose le contrôle, une fois qu'on sait qui le signe.
    private func proposeDelivery() -> Reaction {
        guard let delivery = pendingDelivery else { return offerTheMenu() }

        guard !operatorName.isEmpty else { return askForOperator() }

        pendingDelivery = nil
        return propose(.recordDelivery(
            reading: delivery.reading,
            photo: delivery.photo,
            operatorName: operatorName
        ))
    }

    /// Demande qui contrôle la livraison.
    ///
    /// Jamais sauté : un contrôle sans nom d'opérateur ne vaut rien devant
    /// un inspecteur, et c'est la mention que le cuisinier a signalée comme
    /// la plus importante. Faute de réponse, on le dit au lieu de signer à
    /// la place de quelqu'un.
    private func askForOperator() -> Reaction {
        phase = .awaitingDetail

        switch attempt(.operatorName) {
        case 1:
            return finish(.speak("Qui contrôle la livraison ?"))
        case 2:
            return finish(.speak("Dites juste votre prénom."))
        default:
            pending = nil
            attempts = 0
            operatorName = "Non renseigné"
            return proposeDelivery()
        }
    }

    /// Le prénom dit, débarrassé de ce qui l'entoure.
    ///
    /// Nommée `personName` et non `operatorName` : une propriété stockée et
    /// une fonction ne peuvent pas porter le même nom dans un même type.
    private static func personName(in said: String) -> String {
        let words = said
            .split { !$0.isLetter && $0 != "-" }
            .map(String.init)
            .filter { word in
                let folded = word.folding(
                    options: [.diacriticInsensitive, .caseInsensitive],
                    locale: Locale(identifier: "fr_FR")
                )
                return folded.count > 1 && !nameFillers.contains(folded)
            }

        return words.prefix(2)
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private static let nameFillers: Set<String> = [
        "cest", "est", "je", "suis", "moi", "mon", "prenom", "nom",
        "appelle", "sappelle", "le", "la", "les", "un", "une", "de", "du"
    ]

    /// Quand la demande ne correspond à rien de connu.
    private func offerTheMenu() -> Reaction {
        phase = .awaitingDetail

        switch attempt(.intent) {
        case 1:
            return finish(.speak(
                "Je sais noter un produit entamé, une température, un nettoyage, "
                + "un plat témoin ou une réception. Lequel ?"
            ))
        default:
            // Deux échecs de suite : insister ne donnera rien de plus, et
            // réciter le même menu est précisément ce qui exaspère.
            pending = nil
            attempts = 0
            phase = .idle
            return finish(.stop(
                "Je n'y arrive pas. Touchez le micro et reformulez, "
                + "ou passez par les écrans en dessous."
            ))
        }
    }

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
            // Nom resté vide : on l'a demandé deux fois sans succès, et on
            // ouvre une fiche à remplir plutôt que d'insister.
            guard !name.isEmpty else {
                return "Je n'ai pas saisi le nom. J'ouvre une fiche vide ?"
            }
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

        case .recordDelivery(let reading, _, _):
            let what = reading.summary.isEmpty ? "Bon de livraison lu" : reading.summary
            return "\(what). J'enregistre le contrôle comme acceptée ?"

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
        case .recordDelivery:
            // Ce que la photo ne dit pas, et qui se constate sur le quai.
            return "C'est enregistré. Vérifiez la température et l'état des emballages avant de laisser repartir le livreur."
        case .temperatures: return "J'ouvre les températures."
        case .cleaning:     return "J'ouvre le nettoyage."
        case .foodSample:   return "J'ouvre les plats témoins."
        case .delivery:     return "J'ouvre la réception."
        case .unknown:      return "Je n'ai pas compris."
        }
    }

    // MARK: - Le fil affiché

    private func append(_ speaker: Turn.Speaker, _ text: String, report: AssistantReport? = nil) {
        turns.append(Turn(speaker: speaker, text: text, report: report))
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
        case .show(let report):
            // La conclusion au fil, le détail dans le tableau attaché.
            append(.assistant, report.spoken, report: report)
        case .capture(let text):
            append(.assistant, text)
        case .failed:
            break
        }
        return reaction
    }
}
