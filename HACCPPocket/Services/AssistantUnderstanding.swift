//
//  AssistantUnderstanding.swift
//  HACCPPocket
//
//  Comprendre une phrase dite, et rien de plus.
//
//  ─────────────────────────────────────────────────────────────────────────
//  LA LIMITE QU'ON NE FRANCHIT PAS
//  ─────────────────────────────────────────────────────────────────────────
//
//  Ce fichier reconnaît une intention et un nom de produit. Il ne calcule
//  aucune date, aucune durée de vie, aucun allergène, et n'écrit rien dans
//  le registre.
//
//  Ce n'est pas de la prudence excessive, c'est la règle. Les durées de
//  conservation sont du droit : arrêté du 21 décembre 2009, règlement
//  852/2004. Un modèle de langage qui « propose » une date de retrait
//  produit un registre invérifiable, et c'est précisément ce qu'un
//  contrôleur cherche. Le calcul reste dans le code existant, déterministe,
//  testable, et opposable.
//
//  L'assistant ouvre la bonne porte avec le bon nom déjà écrit. Le reste du
//  travail est fait par ce qui existe déjà et qui a été vérifié.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI UNE STRUCTURE PLUTÔT QU'UNE RÉPONSE EN TEXTE
//  ─────────────────────────────────────────────────────────────────────────
//
//  `@Generable` contraint le modèle à remplir un type Swift. Il ne peut pas
//  répondre autre chose : pas de phrase à analyser, pas de format qui change
//  d'une fois sur l'autre, pas de pseudo-JSON à rattraper. Une action parmi
//  six, un nom, une quantité. Ce qui sort est déjà typé.
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

    /// Ce que l'assistant dit à voix haute.
    ///
    /// Volontairement différent de ce qui est affiché : à l'oreille on
    /// confirme et on demande, à l'écran on détaille. Et la question finale
    /// compte — elle dit que rien n'est encore enregistré.
    var spokenConfirmation: String {
        switch self {
        case .openedProduct(let name, _):
            return name.isEmpty
                ? "Produit entamé. Quel produit ?"
                : "\(name). J'ouvre la fiche ?"
        case .temperatures:
            return "Relevé de température. J'ouvre ?"
        case .cleaning:
            return "Nettoyage. J'ouvre ?"
        case .foodSample:
            return "Plat témoin. J'ouvre ?"
        case .delivery:
            return "Contrôle à réception. J'ouvre ?"
        case .unknown:
            return "Je n'ai pas compris. Vous pouvez répéter ?"
        }
    }
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

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable(description: "Ce qu'un cuisinier demande à son registre d'hygiène")
struct SpokenRequest {

    @Guide(description: "L'action demandée. « autre » si la phrase ne correspond à rien de précis.")
    var intent: SpokenIntent

    @Guide(description: "Le nom de l'aliment, sans la quantité ni l'emballage. Chaîne vide si aucun aliment n'est cité.")
    var productName: String

    @Guide(description: "La quantité ou le conditionnement cité, par exemple « 1 kg ». Chaîne vide si rien n'est cité.")
    var quantity: String
}

#endif

// MARK: - L'interprète

@MainActor
@Observable
final class AssistantUnderstanding {

    enum Outcome: Equatable {
        case idle
        case thinking
        case understood(AssistantAction)
        /// Échoué, avec la raison en clair. Jamais un silence.
        case failed(String)
    }

    private(set) var outcome: Outcome = .idle

    /// Ce qu'on dit au modèle avant toute chose.
    ///
    /// L'interdiction d'inventer une date y figure explicitement. Elle ne
    /// suffirait pas à elle seule — c'est l'absence de champ « date » dans
    /// la structure qui l'empêche réellement — mais les deux ensemble valent
    /// mieux qu'une seule.
    private static let instructions = """
    Tu aides un cuisinier français à remplir son registre d'hygiène.
    À partir de ce qu'il dicte, identifie l'action demandée, le nom de \
    l'aliment et la quantité citée.
    N'invente jamais de date, de durée de conservation ni d'allergène : \
    ce n'est pas ton rôle, l'application les calcule elle-même.
    Si la phrase ne correspond à aucune action connue, réponds « autre ».
    """

    func reset() {
        outcome = .idle
    }

    /// Interprète une phrase dictée.
    func interpret(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            outcome = .idle
            return
        }

        guard IntelligenceAvailability.current.isReady else {
            outcome = .failed(IntelligenceAvailability.current.summary)
            return
        }

        outcome = .thinking

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: Self.instructions)
                let response = try await session.respond(
                    to: trimmed,
                    generating: SpokenRequest.self
                )
                outcome = .understood(Self.action(from: response.content))
            } catch {
                // On montre le message du système plutôt qu'un « erreur » :
                // dépassement de contexte et refus de garde-fou n'appellent
                // pas la même réaction, et seul le texte les distingue.
                outcome = .failed(error.localizedDescription)
            }
            return
        }
        #endif

        outcome = .failed(IntelligenceAvailability.needsNewerSystem.summary)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private static func action(from request: SpokenRequest) -> AssistantAction {
        let name = request.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        let quantity = request.quantity.trimmingCharacters(in: .whitespacesAndNewlines)

        switch request.intent {
        case .produitEntame:
            return .openedProduct(name: name, quantity: quantity)
        case .releveDeTemperature:
            return .temperatures
        case .nettoyage:
            return .cleaning
        case .platTemoin:
            return .foodSample
        case .controleReception:
            return .delivery
        case .autre:
            return .unknown
        }
    }
    #endif
}
