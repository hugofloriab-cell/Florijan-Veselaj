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

    /// Même clé que celle lue par `RootView` pour décider d'afficher l'écran
    /// de bienvenue.
    @AppStorage("haccp.didCompleteOnboarding") private var didCompleteOnboarding = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Les réglages sont présentés en feuille depuis l'accueil et depuis les
    /// registres : sans bouton de fermeture, on y resterait coincé.
    var showsDoneButton: Bool = false

    @Environment(UserPreferences.self) private var preferences
    @Environment(NotificationService.self) private var notificationService
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(InspectorAccess.self) private var inspector
    @Environment(EstablishmentDirectory.self) private var directory
    @Environment(RoleSession.self) private var roles

    @Query private var establishments: [Establishment]

    @State private var showsPaywall = false
    @State private var logoItem: PhotosPickerItem?
    @State private var showsTestAlert = false
    @State private var testScheduled = false
    @State private var newTeamMember = ""
    @State private var inspectorCode = ""
    @State private var codeSaved = false
    @State private var showsInspectorConfirmation = false

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
                        .foregroundStyle(subscription.isSubscribed ? Color.green : Color.brand)
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
    /// Toute modification d'un rappel change cette signature, ce qui relance la
    /// reprogrammation via `.task(id:)`.
    private var schedulingSignature: String {
        preferences.reminders
            .map { "\($0.id.uuidString)-\($0.hour):\($0.minute)-\($0.isEnabled)-\($0.label)" }
            .joined(separator: "|")
    }

    var body: some View {
        NavigationStack {
            Form {
                subscriptionSection
                siteAndRoleSection
                establishmentSection
                contactSection
                logoSection
                operatorSection
                teamSection
                remindersSection
                dataSection
                inspectorSection
                aboutSection
            }
            .navigationTitle("Réglages")
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") { dismiss() }
                    }
                }
            }
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

    // MARK: - Établissement actif et profil

    private var siteAndRoleSection: some View {
        Section {
            NavigationLink {
                SiteSwitcherView()
            } label: {
                HStack(spacing: 12) {
                    RowIcon(systemImage: "building.2", tint: .brand)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Établissement")
                            .font(.subheadline.weight(.medium))
                        Text(directory.activeSite.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if directory.hasMultipleSites {
                        Text("\(directory.sites.count)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            NavigationLink {
                RoleSwitcherView()
            } label: {
                HStack(spacing: 12) {
                    RowIcon(systemImage: roles.role.systemImage, tint: .brand)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Profil")
                            .font(.subheadline.weight(.medium))
                        Text(roles.role.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Cet appareil")
        } footer: {
            Text(directory.hasMultipleSites
                 ? "Tout ce que vous saisissez est enregistré dans le registre de \(directory.activeSite.displayName)."
                 : "Vous pouvez gérer plusieurs établissements : chacun aura son propre registre.")
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

    // MARK: - Contact

    private var contactSection: some View {
        Section {
            TextField(
                "Adresse électronique",
                text: Bindable(preferences).contactEmail
            )
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                // Le même drapeau que celui lu par `RootView` : en créer un
                // second ferait réapparaître l'écran pour l'un et pas pour
                // l'autre.
                didCompleteOnboarding = false
            } label: {
                Label("Revoir l'écran de bienvenue", systemImage: "sparkles")
            }
        } header: {
            Text("Contact")
        } footer: {
            // La nuance compte : présenter cette adresse comme un identifiant
            // de connexion serait un mensonge, et le jour où l'utilisateur
            // changerait de téléphone en pensant « retrouver son compte », il
            // découvrirait qu'il n'y en a jamais eu.
            Text("Cette adresse n'est pas un compte : l'application fonctionne sans connexion et sans serveur, et rien ne vous est demandé pour l'ouvrir. Elle sert à retrouver votre abonnement en cas de changement de téléphone, à pré-remplir vos déclarations d'incident, et à nous joindre.")
        }
    }

    // MARK: - Logo

    // `@ViewBuilder` est indispensable ici : le corps est un `if let` sans
    // `else`, donc sans lui la propriété ne renvoie rien sur un des chemins.
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
            OperatorField(
                name: Bindable(preferences).operatorName,
                placeholder: "Nom de l'opérateur"
            )

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

    // MARK: - Équipe

    private var teamSection: some View {
        Section {
            if preferences.knownOperators.isEmpty {
                Text("Aucun nom enregistré pour l'instant.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(preferences.knownOperators, id: \.self) { name in
                    Button {
                        preferences.selectOperator(name)
                    } label: {
                        HStack {
                            Text(name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if name.caseInsensitiveCompare(preferences.operatorName) == .orderedSame {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.brand)
                            }
                        }
                    }
                }
                .onDelete { preferences.removeOperators(at: $0) }
            }

            HStack {
                TextField("Ajouter une personne", text: $newTeamMember)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onSubmit { addTeamMember() }

                Button {
                    addTeamMember()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.brand)
                        .accessibilityLabel("Ajouter à l'équipe")
                }
                .buttonStyle(.plain)
                .disabled(newTeamMember.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Équipe")
        } footer: {
            Text("Les noms saisis dans les formulaires s'ajoutent tout seuls à cette liste. Appuyez sur un nom pour en faire l'opérateur du moment.")
        }
    }

    private func addTeamMember() {
        let trimmed = newTeamMember.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        preferences.rememberOperator(trimmed)
        newTeamMember = ""
    }

    // MARK: - Données

    private var dataSection: some View {
        Section {
            StoreStatusRow()

            NavigationLink {
                HistoryView()
            } label: {
                Label("Historique complet", systemImage: "clock.arrow.circlepath")
            }

            // Clôtures et sauvegarde touchent l'ensemble du registre : elles
            // restent au gérant.
            if roles.role.canAdminister {
                NavigationLink {
                    IntegrityListView()
                } label: {
                    Label("Intégrité et clôtures", systemImage: "checkmark.seal")
                }

                NavigationLink {
                    BackupView()
                } label: {
                    Label("Sauvegarde et restauration", systemImage: "externaldrive")
                }
            } else {
                Label("Clôtures et sauvegarde réservées au profil Gérant", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Mes données")
        } footer: {
            Text("L'historique retrouve n'importe quel enregistrement passé. La sauvegarde exporte la totalité de l'application dans un fichier.")
        }
    }

    // MARK: - Rappels

    private var remindersSection: some View {
        Section {
            authorizationRow

            if !preferences.meetsMinimumReminders {
                Label(
                    "Moins de deux rappels actifs. Le relevé du matin dit ce qui s'est passé la nuit, celui du soir engage la nuit qui vient : un seul laisse douze heures sans surveillance.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(preferences.reminders) { reminder in
                reminderRow(reminder)
            }
            .onDelete { preferences.removeReminders(at: $0) }

            Button {
                preferences.addReminder()
                Task { await notificationService.requestAuthorizationIfNeeded() }
            } label: {
                Label("Ajouter un rappel", systemImage: "plus")
            }

            Button {
                Task {
                    testScheduled = await notificationService.sendTestNotification(afterSeconds: 10)
                    showsTestAlert = true
                }
            } label: {
                Label("Tester dans 10 secondes", systemImage: "bell.badge.waveform")
            }
            .disabled(!notificationService.isAuthorized)
        } header: {
            Text("Rappels")
        } footer: {
            Text("Créez autant de rappels que votre service en demande : ouverture, coupure, réception, fermeture. Ils sont programmés sur l'appareil et n'utilisent aucune connexion.")
        }
        .alert(
            testScheduled ? "Test programmé" : "Test impossible",
            isPresented: $showsTestAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(testScheduled
                 ? "Verrouillez l'écran ou revenez à l'écran d'accueil : iOS n'affiche pas de bannière tant que l'application est au premier plan."
                 : "Autorisez d'abord les notifications.")
        }
    }

    /// Sans cette ligne, un rappel qui ne part pas restait inexplicable.
    @ViewBuilder
    private var authorizationRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notificationService.isAuthorized ? "bell.badge.fill" : "bell.slash.fill")
                .foregroundStyle(notificationService.isAuthorized ? Color.green : Color.orange)
                .frame(width: 24)
            Text(notificationService.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)

        if notificationService.authorizationStatus == .notDetermined {
            Button {
                Task { await notificationService.requestAuthorization() }
            } label: {
                Label("Autoriser les notifications", systemImage: "bell.badge")
            }
        } else if notificationService.isDenied {
            Button {
                openSystemSettings()
            } label: {
                Label("Ouvrir les réglages d'iOS", systemImage: "arrow.up.forward.app")
            }
        }
    }

    private func reminderRow(_ reminder: ReminderSlot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Intitulé", text: labelBinding(for: reminder))
                    .font(.subheadline.weight(.medium))
                Toggle("", isOn: enabledBinding(for: reminder))
                    .labelsHidden()
                    .accessibilityLabel("Activer \(reminder.label)")
            }

            DatePicker(
                "Heure",
                selection: timeBinding(for: reminder),
                displayedComponents: .hourAndMinute
            )
            .disabled(!reminder.isEnabled)
        }
        .padding(.vertical, 2)
    }

    // MARK: Liaisons vers les rappels

    private func labelBinding(for reminder: ReminderSlot) -> Binding<String> {
        Binding(
            get: { reminder.label },
            set: { newValue in
                var updated = reminder
                updated.label = newValue
                preferences.update(updated)
            }
        )
    }

    private func enabledBinding(for reminder: ReminderSlot) -> Binding<Bool> {
        Binding(
            get: { reminder.isEnabled },
            set: { newValue in
                var updated = reminder
                updated.isEnabled = newValue
                preferences.update(updated)
                if newValue {
                    Task { await notificationService.requestAuthorizationIfNeeded() }
                }
            }
        )
    }

    private func timeBinding(for reminder: ReminderSlot) -> Binding<Date> {
        Binding(
            get: { preferences.time(for: reminder) },
            set: { preferences.setTime($0, for: reminder) }
        )
    }

    private func openSystemSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    // MARK: - Mode inspecteur

    @ViewBuilder
    private var inspectorSection: some View {
        if roles.role.canAdminister {
            Section {
                HStack {
                    SecureField(
                        inspector.hasCode ? "Modifier le code" : "Définir un code (4 chiffres minimum)",
                        text: $inspectorCode
                    )
                    .keyboardType(.numberPad)

                    Button {
                        inspector.setCode(inspectorCode)
                        inspectorCode = ""
                        codeSaved = true
                    } label: {
                        Text("Définir")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.brand)
                    .disabled(inspectorCode.trimmingCharacters(in: .whitespaces).count < 4)
                }

                if codeSaved {
                    Label("Code enregistré", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Button {
                    showsInspectorConfirmation = true
                } label: {
                    Label("Passer en mode consultation", systemImage: "lock.fill")
                }
                .disabled(!inspector.hasCode)
            } header: {
                Text("Mode inspecteur")
            } footer: {
                Text(inspector.hasCode
                     ? "L'application est remplacée par une consultation en lecture seule. Rien n'y est modifiable : il n'y a aucun bouton d'écriture, pas seulement des boutons désactivés. Le code vous permet de reprendre la main."
                     : "Définissez d'abord un code de sortie. Sans lui, n'importe qui pourrait rendre la main sans vous.")
            }
            .alert("Passer en mode consultation ?", isPresented: $showsInspectorConfirmation) {
                Button("Passer en consultation") { inspector.activate() }
                Button("Annuler", role: .cancel) { }
            } message: {
                Text("Vous pourrez reprendre la main avec votre code. Gardez-le en tête : il n'est enregistré nulle part en clair.")
            }
        }
    }

    // MARK: - À propos

    private var aboutSection: some View {
        Section {
            HStack(spacing: 14) {
                BrandLogo(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(BrandAssets.productName)
                        .font(.headline)
                    Text("Traçabilité sanitaire hors ligne")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)

            InfoRow(label: "Stockage", value: "100 % local", systemImage: "iphone")
            InfoRow(label: "Version", value: appVersion, systemImage: "number")
            InfoRow(
                label: "Format des données",
                value: AppSchema.versionDescription,
                systemImage: "cylinder.split.1x2"
            )
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
        .environment(InspectorAccess.shared)
        .environment(EstablishmentDirectory.shared)
        .environment(RoleSession.shared)
}
