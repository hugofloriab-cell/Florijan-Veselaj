//
//  SettingsView.swift
//  HACCPPocket
//
//  Fiche de l'établissement, identité de l'opérateur et rappels quotidiens.
//  Les informations saisies ici alimenteront l'en-tête des exports PDF.
//

import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(UserPreferences.self) private var preferences
    @Environment(NotificationService.self) private var notificationService

    @Query private var establishments: [Establishment]

    private var establishment: Establishment? { establishments.first }

    /// Toute modification d'un réglage de rappel change cette signature, ce qui
    /// relance la reprogrammation via `.task(id:)`.
    private var schedulingSignature: String {
        [
            preferences.remindersEnabled.description,
            "\(preferences.morningHour):\(preferences.morningMinute)",
            "\(preferences.eveningHour):\(preferences.eveningMinute)",
            preferences.expiryDigestEnabled.description,
            "\(preferences.expiryDigestHour)"
        ].joined(separator: "|")
    }

    var body: some View {
        NavigationStack {
            Form {
                establishmentSection
                operatorSection
                remindersSection
                registersSection
                aboutSection
            }
            .navigationTitle("Réglages")
            .task {
                await notificationService.refreshAuthorizationStatus()
                if establishment == nil {
                    modelContext.insert(Establishment())
                    try? modelContext.save()
                }
            }
            .task(id: schedulingSignature) {
                await notificationService.applySchedule(from: preferences)
            }
        }
    }

    // MARK: - Établissement

    @ViewBuilder
    private var establishmentSection: some View {
        if let establishment {
            Section {
                TextField("Raison sociale", text: Bindable(establishment).name)
                TextField("Adresse", text: Bindable(establishment).address, axis: .vertical)
                    .lineLimit(2...4)
                TextField("SIRET", text: Bindable(establishment).siret)
                TextField("Responsable du PMS", text: Bindable(establishment).managerName)
                TextField("Numéro d'agrément (facultatif)", text: Bindable(establishment).approvalNumber)
            } header: {
                Text("Établissement")
            } footer: {
                if establishment.missingFields.isEmpty {
                    Label("Fiche complète", systemImage: "checkmark.seal")
                        .foregroundStyle(.green)
                } else {
                    Text("À compléter avant le premier export : \(establishment.missingFields.joined(separator: ", ")).")
                }
            }
        }
    }

    // MARK: - Opérateur

    private var operatorSection: some View {
        Section {
            TextField("Nom de l'opérateur", text: Bindable(preferences).operatorName)
                .textContentType(.name)

            Stepper(
                "DLC secondaire : \(preferences.defaultShelfLifeDays) jour(s)",
                value: Bindable(preferences).defaultShelfLifeDays,
                in: 1...15
            )
        } header: {
            Text("Saisie")
        } footer: {
            Text("Ces valeurs pré-remplissent les formulaires. La règle des 3 jours après ouverture est la pratique la plus répandue.")
        }
    }

    // MARK: - Rappels

    private var remindersSection: some View {
        Section {
            if !notificationService.isAuthorized {
                Button {
                    Task { await notificationService.requestAuthorization() }
                } label: {
                    Label("Autoriser les notifications", systemImage: "bell.badge")
                }
            }

            Toggle("Rappels des relevés", isOn: Bindable(preferences).remindersEnabled)

            if preferences.remindersEnabled {
                DatePicker("Matin", selection: morningTime, displayedComponents: .hourAndMinute)
                DatePicker("Soir", selection: eveningTime, displayedComponents: .hourAndMinute)
            }

            Toggle("Rappel des DLC", isOn: Bindable(preferences).expiryDigestEnabled)

            if preferences.expiryDigestEnabled {
                Picker("Heure", selection: Bindable(preferences).expiryDigestHour) {
                    ForEach(5..<23, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour)).tag(hour)
                    }
                }
            }
        } header: {
            Text("Rappels")
        } footer: {
            Text(reminderFooter)
        }
    }

    private var reminderFooter: String {
        switch notificationService.authorizationStatus {
        case .denied:
            "Les notifications sont refusées pour HACCP Pocket. Activez-les dans Réglages ▸ Notifications."
        case .authorized, .provisional, .ephemeral:
            "Les rappels sont programmés sur l'appareil. Aucune donnée ne transite par Internet."
        default:
            "Autorisez les notifications pour recevoir les rappels de relevés."
        }
    }

    private var morningTime: Binding<Date> {
        Binding(
            get: { preferences.time(hour: preferences.morningHour, minute: preferences.morningMinute) },
            set: { preferences.setMorning(from: $0) }
        )
    }

    private var eveningTime: Binding<Date> {
        Binding(
            get: { preferences.time(hour: preferences.eveningHour, minute: preferences.eveningMinute) },
            set: { preferences.setEvening(from: $0) }
        )
    }

    // MARK: - Autres registres

    private var registersSection: some View {
        Section("Registres") {
            NavigationLink {
                DeliveryListView()
            } label: {
                Label("Contrôles à réception", systemImage: "shippingbox")
            }
        }
    }

    // MARK: - À propos

    private var aboutSection: some View {
        Section {
            InfoRow(label: "Stockage", value: "100 % local", systemImage: "iphone")
            InfoRow(label: "Version", value: appVersion, systemImage: "number")
        } header: {
            Text("À propos")
        } footer: {
            Text("Toutes vos données restent sur cet appareil. Pensez à activer la sauvegarde iCloud de l'iPhone pour ne rien perdre en cas de casse.")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .modelContainer(AppSchema.preview)
        .environment(UserPreferences.shared)
        .environment(NotificationService.shared)
}
