//
//  UserRole.swift
//  HACCPPocket
//
//  Profils d'utilisation.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUE CES PROFILS SONT, ET CE QU'ILS NE SONT PAS
//  ─────────────────────────────────────────────────────────────────────────
//
//  Ce ne sont pas des comptes, et ce n'est pas de la sécurité. Une
//  application locale posée sur un téléphone de cuisine partagé par toute la
//  brigade ne peut pas prétendre authentifier qui que ce soit.
//
//  Ce sont des garde-fous d'organisation : ils évitent qu'un commis, en
//  cherchant à pointer un nettoyage, tombe sur l'écran de sauvegarde ou
//  supprime un mois de relevés d'un balayage malheureux. Le profil Gérant
//  peut être protégé par un code, ce qui suffit à décourager le geste
//  distrait — et ne prétend rien de plus.
//

import Foundation
import Observation
import CryptoKit

// MARK: - Profil

enum UserRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case manager
    case chef
    case commis

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manager: "Gérant"
        case .chef:    "Chef"
        case .commis:  "Commis"
        }
    }

    var detail: String {
        switch self {
        case .manager:
            "Accès complet : réglages, sauvegarde, clôtures, établissements."
        case .chef:
            "Toute la saisie et la configuration des registres. Pas d'accès à la sauvegarde ni aux clôtures."
        case .commis:
            "Saisie uniquement. Aucune suppression, aucun réglage."
        }
    }

    var systemImage: String {
        switch self {
        case .manager: "person.badge.key"
        case .chef:    "person.crop.circle.badge.checkmark"
        case .commis:  "person"
        }
    }

    // MARK: Ce que chaque profil peut faire

    /// Réglages, sauvegarde, clôtures d'intégrité, gestion des établissements.
    var canAdminister: Bool { self == .manager }

    /// Créer et modifier les enceintes, les tâches de nettoyage, la carte.
    var canConfigureRegisters: Bool { self != .commis }

    /// Supprimer un enregistrement déjà consigné.
    var canDeleteRecords: Bool { self != .commis }
}

// MARK: - Session

@MainActor
@Observable
final class RoleSession {

    static let shared = RoleSession()

    private enum Key {
        static let role = "haccp.role.current"
        static let codeHash = "haccp.role.managerCodeHash"
    }

    private let defaults: UserDefaults

    private(set) var role: UserRole

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let stored = defaults.string(forKey: Key.role).flatMap(UserRole.init(rawValue:))
        // Sans choix explicite, on ouvre en Gérant : verrouiller quelqu'un
        // hors de son propre outil au premier lancement serait absurde.
        self.role = stored ?? .manager
    }

    // MARK: Code du profil Gérant

    var hasManagerCode: Bool {
        !(defaults.string(forKey: Key.codeHash) ?? "").isEmpty
    }

    func setManagerCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 4 else { return }
        defaults.set(Self.hash(trimmed), forKey: Key.codeHash)
    }

    func removeManagerCode() {
        defaults.removeObject(forKey: Key.codeHash)
    }

    private func matchesManagerCode(_ code: String) -> Bool {
        guard let stored = defaults.string(forKey: Key.codeHash), !stored.isEmpty else {
            return true
        }
        return stored == Self.hash(code.trimmingCharacters(in: .whitespaces))
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: Bascule

    /// Descendre en Chef ou en Commis ne demande rien : c'est se restreindre.
    /// Remonter en Gérant demande le code, s'il en existe un.
    @discardableResult
    func switchTo(_ newRole: UserRole, code: String = "") -> Bool {
        if newRole == .manager && role != .manager {
            guard matchesManagerCode(code) else { return false }
        }

        role = newRole
        defaults.set(newRole.rawValue, forKey: Key.role)
        return true
    }

    var requiresCodeToBecomeManager: Bool {
        role != .manager && hasManagerCode
    }
}
