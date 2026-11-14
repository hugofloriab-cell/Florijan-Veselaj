//
//  VoiceKeychain.swift
//  HACCPPocket
//
//  La clé de la voix en ligne, rangée dans le trousseau.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI PAS DANS LE CODE, NI DANS LES RÉGLAGES ORDINAIRES
//  ─────────────────────────────────────────────────────────────────────────
//
//  Une clé d'API écrite dans le code part avec l'application sur l'App
//  Store. Un binaire se décompresse, les chaînes se lisent, et la clé sert
//  alors à n'importe qui — facturée à celui qui l'a publiée.
//
//  `UserDefaults` n'est pas mieux : le fichier de préférences se lit dans
//  une sauvegarde iTunes ou sur un appareil débridé.
//
//  Le trousseau chiffre la valeur, la lie à cet appareil, et la retire de
//  toute sauvegarde non chiffrée. C'est le seul endroit correct, et il
//  tient en quarante lignes.
//

import Foundation
import Security

enum VoiceKeychain {

    private static let service = "fr.haccppocket.voice"
    private static let account = "elevenlabs.apiKey"

    /// La clé enregistrée, ou `nil`.
    static var apiKey: String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8)
        else { return nil }

        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Enregistre la clé, ou l'efface si la chaîne est vide.
    @discardableResult
    static func store(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            SecItemDelete(baseQuery as CFDictionary)
            return true
        }

        // Le trousseau n'écrase pas : on retire avant d'écrire, ce qui
        // évite un `errSecDuplicateItem` sur une seconde saisie.
        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecValueData as String] = Data(trimmed.utf8)
        // Lisible seulement quand l'appareil est déverrouillé, et jamais
        // transférée vers un autre iPhone par une sauvegarde.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static var hasKey: Bool { apiKey != nil }

    /// Les quatre derniers caractères, pour montrer qu'une clé est là sans
    /// la révéler.
    static var redacted: String? {
        guard let key = apiKey, key.count > 4 else { return nil }
        return "••••" + key.suffix(4)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
