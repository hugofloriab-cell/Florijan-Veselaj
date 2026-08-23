//
//  UserPreferences.swift
//  HACCPPocket
//
//  Réglages utilisateur persistés dans UserDefaults : identité de l'opérateur,
//  durée de vie secondaire par défaut, et la liste des rappels quotidiens.
//

import Foundation
import Observation

// MARK: - Rappel

/// Un rappel quotidien librement défini par l'utilisateur. Les horaires de
/// travail d'une cuisine ne se résument pas à « matin » et « soir » : coupure
/// de service, réception de 14 h, contrôle de fin de mise en place…
struct ReminderSlot: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var label: String
    var hour: Int
    var minute: Int
    var isEnabled: Bool = true

    var components: DateComponents {
        DateComponents(hour: hour, minute: minute)
    }

    /// Ex. « 08:30 »
    var formattedTime: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// Identifiant de la notification correspondante.
    var notificationIdentifier: String {
        "haccp.reminder.\(id.uuidString)"
    }

    static func defaults() -> [ReminderSlot] {
        [
            ReminderSlot(label: "Relevé du matin", hour: 8, minute: 30),
            ReminderSlot(label: "Relevé du soir", hour: 19, minute: 0),
            ReminderSlot(label: "Contrôle des DLC", hour: 9, minute: 0)
        ]
    }
}

// MARK: - Préférences

@MainActor
@Observable
final class UserPreferences {

    static let shared = UserPreferences()

    private enum Key {
        static let operatorName = "haccp.operatorName"
        static let shelfLifeDays = "haccp.defaultShelfLifeDays"
        static let reminders = "haccp.reminders.v2"
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

    /// Rappels quotidiens, dans l'ordre chronologique.
    var reminders: [ReminderSlot] {
        didSet { persistReminders() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.operatorName = defaults.string(forKey: Key.operatorName) ?? ""
        self.defaultShelfLifeDays = (defaults.object(forKey: Key.shelfLifeDays) as? Int)
            ?? TrackedProduct.defaultShelfLifeDays

        if let data = defaults.data(forKey: Key.reminders),
           let decoded = try? JSONDecoder().decode([ReminderSlot].self, from: data) {
            self.reminders = decoded
        } else {
            self.reminders = ReminderSlot.defaults()
        }
    }

    private func persistReminders() {
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        defaults.set(data, forKey: Key.reminders)
    }

    // MARK: - Édition des rappels

    var enabledReminders: [ReminderSlot] {
        reminders.filter(\.isEnabled)
    }

    func addReminder(label: String = "Nouveau rappel", hour: Int = 12, minute: Int = 0) {
        reminders.append(ReminderSlot(label: label, hour: hour, minute: minute))
        sortReminders()
    }

    func removeReminders(at offsets: IndexSet) {
        reminders.remove(atOffsets: offsets)
    }

    func update(_ reminder: ReminderSlot) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        reminders[index] = reminder
        sortReminders()
    }

    private func sortReminders() {
        reminders.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    // MARK: - Conversions pour les DatePicker

    func date(hour: Int, minute: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    func time(for reminder: ReminderSlot) -> Date {
        date(hour: reminder.hour, minute: reminder.minute)
    }

    func setTime(_ date: Date, for reminder: ReminderSlot, calendar: Calendar = .current) {
        var updated = reminder
        updated.hour = calendar.component(.hour, from: date)
        updated.minute = calendar.component(.minute, from: date)
        update(updated)
    }
}
