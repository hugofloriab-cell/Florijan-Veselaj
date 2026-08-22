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

    @Query(sort: \Equipment.sortIndex) private var equipments: [Equipment]
    @Query private var products: [TrackedProduct]
    @Query(sort: \CleaningTask.sortIndex) private var cleaningTasks: [CleaningTask]

    /// Relevé que l'utilisateur vient de sélectionner : ouvre la feuille de saisie.
    @State private var entryTarget: PendingReading?

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
                summarySection
                alertsSection
                pendingReadingsSection
                expiringProductsSection
                cleaningSection
            }
            .navigationTitle("Aujourd'hui")
            .navigationBarTitleDisplayMode(.large)
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
            ProgressRow(
                title: "Relevés de température",
                completed: dashboard.completedReadingsToday,
                total: dashboard.expectedReadingsToday
            )

            InfoRow(
                label: "Opérations de nettoyage dues",
                value: "\(dashboard.dueCleaningTasks.count)",
                systemImage: "sparkles"
            )

            InfoRow(
                label: "Produits entamés",
                value: "\(dashboard.openProductsCount)",
                systemImage: "shippingbox"
            )

            if let rate = dashboard.complianceRate() {
                HStack {
                    Image(systemName: "checkmark.seal")
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    Text("Conformité sur 30 jours")
                    Spacer()
                    Text(rate.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .foregroundStyle(rate >= 0.95 ? .green : .orange)
                }
            }
        } header: {
            Text(AppFormatters.longDay(.now).capitalized)
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
                        entryTarget = pending
                    } label: {
                        HStack {
                            Image(systemName: pending.equipment.type.systemImage)
                                .foregroundStyle(.teal)
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
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name)
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
                    }
                }
            }
        }
    }

    // MARK: - Nettoyage

    @ViewBuilder
    private var cleaningSection: some View {
        if !dashboard.dueCleaningTasks.isEmpty {
            Section("Nettoyage à réaliser") {
                ForEach(dashboard.dueCleaningTasks.prefix(5).map { $0 }) { task in
                    HStack {
                        Image(systemName: task.frequency.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
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
            }
        }
    }
}

#Preview {
    DashboardView()
        .modelContainer(AppSchema.preview)
        .environment(UserPreferences.shared)
}
