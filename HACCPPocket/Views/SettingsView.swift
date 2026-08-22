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
import PhotosUI

#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(UserPreferences.self) private var preferences
    @Environment(NotificationService.self) private var notificationService
    @Environment(SubscriptionManager.self) private var subscription

    @Query private var establishments: [Establishment]

    @State private var showsPaywall = false
    @State private var logoItem: PhotosPickerItem?

    private var establishment: Establishment? { establishments.first }

    // MARK: - Abonnement

    private var subscriptionSection: some View {
        Section {
            Button {
                showsPaywall = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: subscription.isSubscribed ? "checkmark.seal.fill" : "sparkles")
                        .font(.title3)
                        .foregroundStyle(subscription.isSubscribed ? Color.green : Color.teal)
                        .frame(width: 26)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(subscription.statusTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(subscription.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            if !subscription.isSubscribed {
                Button("Restaurer mes achats") {
                    Task { await subscription.restorePurchases() }
                }
                .disabled(subscription.isPurchasing)
            }
        } header: {
            Text("Abonnement")
        } footer: {
            if subscription.isSubscribed {
                Text("Gérez ou résiliez votre abonnement dans Réglages ▸ votre nom ▸ Abonnements.")
            } else {
                Text("Pendant l'essai, l'application est complète. Ensuite, la consultation et l'export restent accessibles.")
            }
        }
    }

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
                subscriptionSection
                establishmentSection
                logoSection
                operatorSection
                remindersSection
                aboutSection
            }
            .navigationTitle("Réglages")
            .sheet(isPresented: $showsPaywall) {
                PaywallView()
            }
            .task {
                await notificationService.refreshAuthorizationStatus()
                await subscription.refreshEntitlements()
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

    // MARK: - Logo

    @ViewBuilder
    private var logoSection: some View {
        if let establishment {
            Section {
                if let data = establishment.logoData, let image = logoImage(from: data) {
                    HStack {
                        Spacer()
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 80)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                PhotosPicker(selection: $logoItem, matching: .images) {
                    Label(
                        establishment.logoData == nil ? "Choisir un logo" : "Remplacer le logo",
                        systemImage: "photo"
                    )
                }

                if establishment.logoData != nil {
                    Button("Retirer le logo", role: .destructive) {
                        establishment.logoData = nil
                        establishment.touch()
                        try? modelContext.save()
                    }
                }
            } header: {
                Text("Logo")
            } footer: {
                Text("Le logo apparaît en en-tête du registre mensuel exporté en PDF.")
            }
            .onChange(of: logoItem) { _, newItem in
                Task { await loadLogo(newItem, into: establishment) }
            }
        }
    }

    private func logoImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }

    private func loadLogo(_ item: PhotosPickerItem?, into establishment: Establishment) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        establishment.logoData = data
        establishment.touch()
        try? modelContext.save()
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
        .environment(SubscriptionManager.shared)
        .environment(NotificationService.shared)
}
