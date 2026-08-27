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

    /// Deux relevés par jour au minimum : celui du matin dit ce qui s'est
    /// passé la nuit, celui du soir engage la nuit qui vient. Un seul relevé
    /// quotidien laisse douze heures sans surveillance.
    static let minimumDailyCount = 2

    static func defaults() -> [ReminderSlot] {
        [
            ReminderSlot(label: "Relevé du matin", hour: 8, minute: 30),
            ReminderSlot(label: "Nettoyage du midi", hour: 15, minute: 0),
            ReminderSlot(label: "Relevé du soir", hour: 19, minute: 0),
            ReminderSlot(label: "Nettoyage de fermeture", hour: 22, minute: 30),
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
        static let knownOperators = "haccp.operators.v1"
        static let contactEmail = "haccp.contactEmail"
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

    /// L'équipe. Une cuisine n'est jamais tenue par une seule personne, et la
    /// traçabilité impose de savoir qui a fait quoi : chaque formulaire doit
    /// pouvoir désigner l'opérateur en un geste, sans le retaper.
    var knownOperators: [String] {
        didSet { defaults.set(knownOperators, forKey: Key.knownOperators) }
    }

    /// Adresse de contact du responsable.
    ///
    /// ⚠️ Ce n'est PAS un identifiant de connexion, et l'application ne
    /// prétend pas le contraire. Vérifier qu'une adresse appartient bien à
    /// celui qui la saisit demande d'envoyer un message et d'en attendre la
    /// réponse, donc un serveur — ce que cette application n'a pas et n'aura
    /// pas, c'est le choix de départ.
    ///
    /// Elle sert à trois choses concrètes : pré-remplir l'expéditeur des
    /// déclarations d'incident, retrouver un achat auprès de l'App Store en
    /// cas de changement de téléphone, et savoir qui contacter pour du
    /// support. Rien de plus, et rien n'en dépend pour ouvrir l'application.
    var contactEmail: String {
        didSet { defaults.set(contactEmail, forKey: Key.contactEmail) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.operatorName = defaults.string(forKey: Key.operatorName) ?? ""
        self.defaultShelfLifeDays = (defaults.object(forKey: Key.shelfLifeDays) as? Int)
            ?? TrackedProduct.defaultShelfLifeDays

        self.knownOperators = defaults.stringArray(forKey: Key.knownOperators) ?? []
        self.contactEmail = defaults.string(forKey: Key.contactEmail) ?? ""

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

    /// Le plan de surveillance tient-il le minimum de deux rappels par jour ?
    var meetsMinimumReminders: Bool {
        enabledReminders.count >= ReminderSlot.minimumDailyCount
    }

    func addReminder(label: String = "Nouveau rappel", hour: Int = 12, minute: Int = 0) {
        reminders.append(ReminderSlot(label: label, hour: hour, minute: minute))
        sortReminders()
    }

    /// `remove(atOffsets:)` est fourni par SwiftUI ; ce fichier ne décrit que
    /// des données et n'a pas à en dépendre. La suppression se fait donc à la
    /// main, en partant de la fin pour ne pas décaler les index restants.
    func removeReminders(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where reminders.indices.contains(index) {
            reminders.remove(at: index)
        }
    }

    func update(_ reminder: ReminderSlot) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        reminders[index] = reminder
        sortReminders()
    }

    private func sortReminders() {
        reminders.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    // MARK: - Équipe

    /// Enregistre un nom dans l'équipe s'il est nouveau. Appelé après chaque
    /// saisie : la liste se construit toute seule à l'usage, personne n'a à
    /// remplir un annuaire avant de commencer.
    func rememberOperator(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !knownOperators.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }

        knownOperators.append(trimmed)
        knownOperators.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func removeOperators(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where knownOperators.indices.contains(index) {
            knownOperators.remove(at: index)
        }
    }

    /// Désigne l'opérateur du moment : il devient le nom pré-rempli partout.
    func selectOperator(_ name: String) {
        rememberOperator(name)
        operatorName = name
    }

    /// Noms proposés dans les formulaires, l'opérateur courant en tête.
    var operatorSuggestions: [String] {
        var names = knownOperators
        let current = operatorName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty {
            names.removeAll { $0.caseInsensitiveCompare(current) == .orderedSame }
            names.insert(current, at: 0)
        }
        return names
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
