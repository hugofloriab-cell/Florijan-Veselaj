//
//  IntelligenceAvailability.swift
//  HACCPPocket
//
//  Le modèle de langage embarqué est-il utilisable ici, maintenant ?
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI UN FICHIER ENTIER POUR UNE QUESTION
//  ─────────────────────────────────────────────────────────────────────────
//
//  Parce que la réponse dépend de trois choses indépendantes — la version
//  d'iOS, le modèle d'iPhone, et un téléchargement peut-être en cours — et
//  que chacune appelle un message différent. Les confondre en un « ça ne
//  marche pas » laisserait l'utilisateur sans rien à faire.
//
//  L'application vise iOS 17 ; `FoundationModels` existe depuis iOS 26. Tout
//  ce qui le touche est donc gardé deux fois : à la compilation par
//  `canImport`, à l'exécution par `#available`. Un iPhone sous iOS 17 ne
//  doit pas seulement éviter de planter — il doit afficher autre chose.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum IntelligenceAvailability: Equatable {

    /// Le modèle répond. C'est le seul cas où l'assistant peut comprendre.
    case ready

    /// iOS est trop ancien. Rien à faire sauf mettre à jour.
    case needsNewerSystem

    /// L'appareil n'est pas éligible à Apple Intelligence. Définitif.
    case deviceNotEligible

    /// Le modèle se télécharge, ou le système est occupé. Temporaire.
    case notReady

    /// Autre chose — on affiche la raison brute plutôt que de l'inventer.
    case other(String)

    static var current: IntelligenceAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .ready
            case .unavailable(.deviceNotEligible):
                return .deviceNotEligible
            case .unavailable(.modelNotReady):
                return .notReady
            case .unavailable(let reason):
                return .other(String(describing: reason))
            }
        }
        #endif
        return .needsNewerSystem
    }

    var isReady: Bool { self == .ready }

    /// Ce que l'écran affiche. Écrit pour un cuisinier, pas pour moi.
    var summary: String {
        switch self {
        case .ready:
            return "Assistant disponible"
        case .needsNewerSystem:
            return "Nécessite iOS 26 ou plus récent"
        case .deviceNotEligible:
            return "Cet iPhone ne gère pas Apple Intelligence"
        case .notReady:
            return "Modèle en cours de préparation"
        case .other:
            return "Assistant momentanément indisponible"
        }
    }

    /// La suite à donner, quand il y en a une.
    var advice: String? {
        switch self {
        case .ready:
            return nil
        case .needsNewerSystem:
            return "Réglages → Général → Mise à jour logicielle."
        case .deviceNotEligible:
            return "Apple Intelligence demande un iPhone 15 Pro ou plus récent. Tous les onglets restent accessibles à la main, comme aujourd'hui."
        case .notReady:
            return "Vérifiez qu'Apple Intelligence est activé dans Réglages, puis réessayez dans quelques minutes. Le premier téléchargement se fait en Wi-Fi, appareil branché."
        case .other(let reason):
            return "Raison signalée par le système : \(reason)"
        }
    }

    var systemImage: String {
        switch self {
        case .ready:             return "checkmark.circle.fill"
        case .notReady:          return "clock.badge.exclamationmark"
        case .needsNewerSystem:  return "arrow.down.circle"
        case .deviceNotEligible: return "iphone.slash"
        case .other:             return "exclamationmark.triangle"
        }
    }
}
