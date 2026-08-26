//
//  InspectorAccess.swift
//  HACCPPocket
//
//  Mode inspecteur : une interface verrouillée, en lecture seule.
//
//  Un contrôleur doit pouvoir parcourir les registres sans qu'on lui tende un
//  téléphone déverrouillé sur lequel il peut, involontairement, cocher une
//  case ou supprimer une ligne. Le mode inspecteur remplace l'application par
//  une consultation : il n'y a pas de bouton à désactiver, il n'y a
//  simplement aucun bouton d'écriture.
//
//  Le code de sortie protège contre le geste accidentel et contre la sortie
//  discrète, pas contre quelqu'un qui aurait le téléphone en main pendant
//  une heure. L'application ne prétend pas le contraire.
//

import Foundation
import Observation
import CryptoKit

@MainActor
@Observable
final class InspectorAccess {

    static let shared = InspectorAccess()

    private enum Key {
        static let isActive = "haccp.inspector.active"
        static let codeHash = "haccp.inspector.codeHash"
        static let activatedAt = "haccp.inspector.activatedAt"
    }

    private let defaults: UserDefaults

    /// L'application est-elle en consultation verrouillée ?
    private(set) var isActive: Bool

    /// Début de la session de consultation, affiché au contrôleur.
    private(set) var activatedAt: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isActive = defaults.bool(forKey: Key.isActive)

        let timestamp = defaults.double(forKey: Key.activatedAt)
        self.activatedAt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    // MARK: - Code de sortie

    /// Un code a-t-il été défini ?
    var hasCode: Bool {
        !(defaults.string(forKey: Key.codeHash) ?? "").isEmpty
    }

    /// Enregistre le code de sortie. Seule l'empreinte est conservée : le
    /// code lui-même n'est écrit nulle part.
    func setCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 4 else { return }
        defaults.set(Self.hash(trimmed), forKey: Key.codeHash)
    }

    func removeCode() {
        defaults.removeObject(forKey: Key.codeHash)
    }

    private func matches(_ code: String) -> Bool {
        guard let stored = defaults.string(forKey: Key.codeHash), !stored.isEmpty else {
            // Sans code défini, on ne bloque personne : ce serait enfermer
            // l'utilisateur dans son propre outil.
            return true
        }
        return stored == Self.hash(code.trimmingCharacters(in: .whitespaces))
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: - Entrée et sortie

    func activate() {
        isActive = true
        activatedAt = .now
        defaults.set(true, forKey: Key.isActive)
        defaults.set(activatedAt?.timeIntervalSince1970 ?? 0, forKey: Key.activatedAt)
    }

    /// Renvoie `false` si le code ne correspond pas — la vue reste alors sur
    /// place et affiche l'erreur.
    @discardableResult
    func deactivate(using code: String) -> Bool {
        guard matches(code) else { return false }

        isActive = false
        activatedAt = nil
        defaults.set(false, forKey: Key.isActive)
        defaults.removeObject(forKey: Key.activatedAt)
        return true
    }

    /// Durée de la consultation en cours, en minutes.
    func sessionMinutes(at reference: Date = .now) -> Int {
        guard let activatedAt else { return 0 }
        return max(0, Int(reference.timeIntervalSince(activatedAt) / 60))
    }
}
