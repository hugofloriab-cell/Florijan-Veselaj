//
//  UserPreferences.swift
//  HACCPPocket
//
//  Réglages utilisateur persistés dans UserDefaults : identité de l'opérateur,
//  durée de vie secondaire par défaut, horaires des rappels. Observable, donc
//  toute vue qui le lit se rafraîchit automatiquement.
//

import Foundation
import Observation

@MainActor
@Observable
final class UserPreferences {

    static let shared = UserPreferences()

    private enum Key {
        static let operatorName = "haccp.operatorName"
        static let shelfLifeDays = "haccp.defaultShelfLifeDays"
        static let remindersEnabled = "haccp.remindersEnabled"
        static let morningHour = "haccp.morningHour"
        static let morningMinute = "haccp.morningMinute"
        static let eveningHour = "haccp.eveningHour"
        static let eveningMinute = "haccp.eveningMinute"
        static let expiryDigestHour = "haccp.expiryDigestHour"
        static let expiryDigestEnabled = "haccp.expiryDigestEnabled"
    }

    private let defaults: UserDefaults

    /// Nom pré-rempli dans tous les formulaires de traçabilité.
    var operatorName: String {
        didSet { defaults.set(operatorName, forKey: Key.operatorName) }
    }

    /// Durée de vie appliquée par défaut après ouverture d'un produit.
    var defaultShelfLifeDays: Int {
        didSet { defaults.set(defaultShelfLifeDays, forKey: Key.shelfLifeDays) }
    }

    var remindersEnabled: Bool {
        didSet { defaults.set(remindersEnabled, forKey: Key.remindersEnabled) }
    }

    var morningHour: Int {
        didSet { defaults.set(morningHour, forKey: Key.morningHour) }
    }

    var morningMinute: Int {
        didSet { defaults.set(morningMinute, forKey: Key.morningMinute) }
    }

    var eveningHour: Int {
        didSet { defaults.set(eveningHour, forKey: Key.eveningHour) }
    }

    var eveningMinute: Int {
        didSet { defaults.set(eveningMinute, forKey: Key.eveningMinute) }
    }

    var expiryDigestEnabled: Bool {
        didSet { defaults.set(expiryDigestEnabled, forKey: Key.expiryDigestEnabled) }
    }

    var expiryDigestHour: Int {
        didSet { defaults.set(expiryDigestHour, forKey: Key.expiryDigestHour) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // `object(forKey:)` distingue « absent » de « valeur 0 », contrairement
        // à `integer(forKey:)` qui renverrait 0 au premier lancement.
        self.operatorName = defaults.string(forKey: Key.operatorName) ?? ""
        self.defaultShelfLifeDays = (defaults.object(forKey: Key.shelfLifeDays) as? Int)
            ?? TrackedProduct.defaultShelfLifeDays
        self.remindersEnabled = (defaults.object(forKey: Key.remindersEnabled) as? Bool) ?? true
        self.morningHour = (defaults.object(forKey: Key.morningHour) as? Int) ?? 8
        self.morningMinute = (defaults.object(forKey: Key.morningMinute) as? Int) ?? 30
        self.eveningHour = (defaults.object(forKey: Key.eveningHour) as? Int) ?? 19
        self.eveningMinute = (defaults.object(forKey: Key.eveningMinute) as? Int) ?? 0
        self.expiryDigestEnabled = (defaults.object(forKey: Key.expiryDigestEnabled) as? Bool) ?? true
        self.expiryDigestHour = (defaults.object(forKey: Key.expiryDigestHour) as? Int) ?? 9
    }
}

// MARK: - Conversion en composantes de date

extension UserPreferences {

    var morningComponents: DateComponents {
        DateComponents(hour: morningHour, minute: morningMinute)
    }

    var eveningComponents: DateComponents {
        DateComponents(hour: eveningHour, minute: eveningMinute)
    }

    var expiryDigestComponents: DateComponents {
        DateComponents(hour: expiryDigestHour, minute: 0)
    }

    /// Heure de rappel exprimée en `Date`, pour l'affichage dans un `DatePicker`.
    func time(hour: Int, minute: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    func setMorning(from date: Date, calendar: Calendar = .current) {
        morningHour = calendar.component(.hour, from: date)
        morningMinute = calendar.component(.minute, from: date)
    }

    func setEvening(from date: Date, calendar: Calendar = .current) {
        eveningHour = calendar.component(.hour, from: date)
        eveningMinute = calendar.component(.minute, from: date)
    }
}
