//
//  DashboardView.swift
//  HACCPPocket
//
//  Écran d'accueil : ce qu'il reste à faire aujourd'hui, et ce qui cloche.
//  Toute la logique vient de `DashboardViewModel`, recalculé à chaque
//  rafraîchissement des `@Query`.
//

import SwiftUI
import SwiftData

struct DashboardView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(AppRouter.self) private var router

    @Query(sort: \Equipment.sortIndex) private var equipments: [Equipment]
    @Query private var products: [TrackedProduct]
    @Query(sort: \CleaningTask.sortIndex) private var cleaningTasks: [CleaningTask]

    /// Relevé que l'utilisateur vient de sélectionner : ouvre la feuille de saisie.
    @State private var entryTarget: PendingReading?
    @State private var showsPaywall = false
    @State private var editedProduct: TrackedProduct?
    @State private var cleaningViewModel: CleaningPlanViewModel?

    private var dashboard: DashboardViewModel {
        DashboardViewModel(
            equipments: equipments,
            products: products,
            cleaningTasks: cleaningTasks
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if !subscription.isSubscribed {
                    Section {
                        SubscriptionBanner { showsPaywall = true }
                    }
                }
                summarySection
                alertsSection
                pendingReadingsSection
                expiringProductsSection
                cleaningSection
                registersSection
            }
            .navigationTitle("Aujourd'hui")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showsPaywall) {
                PaywallView()
            }
            .sheet(item: $editedProduct) { product in
                ProductFormView(product: product, context: modelContext)
            }
            .task {
                if cleaningViewModel == nil {
                    cleaningViewModel = CleaningPlanViewModel(context: modelContext)
                }
            }
            .sheet(item: $entryTarget) { target in
                TemperatureEntryView(
                    equipment: target.equipment,
                    moment: target.moment,
                    context: modelContext
                )
            }
            .overlay {
                if equipments.isEmpty {
                    ContentUnavailableView(
                        "Aucun équipement",
                        systemImage: "refrigerator",
                        description: Text("Ajoutez vos enceintes dans l'onglet Températures pour démarrer le suivi.")
                    )
                }
            }
        }
    }

    // MARK: - En-tête

    private var summarySection: some View {
        Section {
            // Chaque ligne renvoie sur l'onglet concerné : lire « 3 opérations
            // dues » sans pouvoir y aller d'un geste n'a aucun intérêt.
            Button {
                router.show(.temperatures)
            } label: {
                HStack {
                    ProgressRow(
                        title: "Relevés de température",
                        completed: dashboard.completedReadingsToday,
                        total: dashboard.expectedReadingsToday
                    )
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Button {
                router.show(.cleaning)
            } label: {
                HStack {
                    InfoRow(
                        label: "Opérations de nettoyage dues",
                        value: "\(dashboard.dueCleaningTasks.count)",
                        systemImage: "sparkles"
                    )
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Button {
                router.show(.products)
            } label: {
                HStack {
                    InfoRow(
                        label: "Produits entamés",
                        value: "\(dashboard.openProductsCount)",
                        systemImage: "shippingbox"
                    )
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if let rate = dashboard.complianceRate() {
                HStack {
                    Image(systemName: "checkmark.seal")
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    Text("Conformité sur 30 jours")
                    Spacer()
                    Text(rate.formatted(.percent.precision(.fractionLength(0)).locale(AppFormatters.locale)))
                        .monospacedDigit()
                        .foregroundStyle(rate >= 0.95 ? Color.green : Color.orange)
                }
            }
        } header: {
            Text(AppFormatters.sentenceCased(AppFormatters.longDay(.now)))
        }
    }

    // MARK: - Alertes

    @ViewBuilder
    private var alertsSection: some View {
        if dashboard.alerts.isEmpty {
            Section {
                Label("Aucune anomalie en cours", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
        } else {
            Section("Alertes") {
                ForEach(dashboard.alerts) { alert in
                    AlertRow(alert: alert)
                }
            }
        }
    }

    // MARK: - Relevés à saisir

    @ViewBuilder
    private var pendingReadingsSection: some View {
        if dashboard.pendingReadings.isEmpty {
            if !equipments.isEmpty {
                Section("Relevés de température") {
                    Label("Tous les relevés du jour sont faits", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        } else {
            Section("Relevés à saisir") {
                ForEach(dashboard.pendingReadings) { pending in
                    Button {
                        if subscription.canWrite {
                            entryTarget = pending
                        } else {
                            showsPaywall = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: pending.equipment.type.systemImage)
                                .foregroundStyle(.brand)
                                .frame(width: 26)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(pending.equipment.name)
                                    .foregroundStyle(.primary)
                                Text(pending.equipment.formattedRange)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            StatusBadge(
                                text: pending.moment.label,
                                color: pending.moment.accentColor,
                                systemImage: pending.moment.systemImage
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Produits à traiter

    @ViewBuilder
    private var expiringProductsSection: some View {
        let urgent = dashboard.expiredProducts + dashboard.expiringProducts
        if !urgent.isEmpty {
            Section("Produits à traiter") {
                ForEach(urgent) { product in
                    Button {
                        if subscription.canWrite {
                            editedProduct = product
                        } else {
                            showsPaywall = true
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.name)
                                    .foregroundStyle(.primary)
                                Text(product.storage.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusBadge(
                                text: product.remainingLabel(),
                                color: product.urgency().color,
                                systemImage: product.urgency().systemImage
                            )
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    /// Pointe une opération depuis l'accueil, sans passer par l'onglet Nettoyage.
    private func completeCleaning(_ task: CleaningTask) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        cleaningViewModel?.complete(task)
    }

    // MARK: - Autres registres

    private var registersSection: some View {
        Section("Registres") {
            NavigationLink {
                DeliveryListView()
            } label: {
                Label("Contrôles à réception", systemImage: "shippingbox")
            }

            NavigationLink {
                ReportView()
            } label: {
                Label("Registre mensuel (PDF)", systemImage: "doc.text")
            }
        }
    }

    // MARK: - Nettoyage

    @ViewBuilder
    private var cleaningSection: some View {
        if !dashboard.dueCleaningTasks.isEmpty {
            Section("Nettoyage à réaliser") {
                ForEach(dashboard.dueCleaningTasks.prefix(5).map { $0 }) { task in
                    Button {
                        completeCleaning(task)
                    } label: {
                        HStack {
                            Image(systemName: "circle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .foregroundStyle(.primary)
                                if !task.zone.isEmpty {
                                    Text(task.zone)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if task.isOverdue() {
                                StatusBadge(text: "En retard", color: .orange)
                            }
                        }
                    }
                    .accessibilityLabel("Pointer \(task.title)")
                }
            }
        }
    }
}

#Preview {
    DashboardView()
        .modelContainer(AppSchema.preview)
        .environment(UserPreferences.shared)
        .environment(SubscriptionManager.shared)
}
