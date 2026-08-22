//
//  ContentView.swift
//  HACCPPocket
//
//  ⚠️ ÉCRAN TEMPORAIRE (Steps A et B).
//  Il vérifie que le schéma SwiftData se charge et que les ViewModels
//  produisent la bonne synthèse. Il sera intégralement remplacé par la vraie
//  navigation à racine au Step C.
//

import SwiftUI
import SwiftData

struct ContentView: View {

    @Environment(\.modelContext) private var modelContext

    /// Optionnel : la Preview de cet écran n'injecte pas forcément les réglages.
    @Environment(UserPreferences.self) private var preferences: UserPreferences?

    @Query(sort: \Equipment.sortIndex) private var equipments: [Equipment]
    @Query(sort: \CleaningTask.sortIndex) private var cleaningTasks: [CleaningTask]
    @Query(sort: \TrackedProduct.secondaryLimitDate) private var products: [TrackedProduct]
    @Query(sort: \DeliveryCheck.receivedAt, order: .reverse) private var deliveries: [DeliveryCheck]
    @Query private var establishments: [Establishment]

    /// La synthèse est recalculée à chaque rafraîchissement des `@Query`.
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
                diagnosticSection
                equipmentsSection
                productsSection
            }
            .navigationTitle("HACCP Pocket")
        }
    }

    // MARK: - Synthèse du jour

    private var summarySection: some View {
        Section("Synthèse du jour") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Relevés de température")
                    Spacer()
                    Text("\(dashboard.completedReadingsToday) / \(dashboard.expectedReadingsToday)")
                        .monospacedDigit()
                        .foregroundStyle(dashboard.isReadingRoutineComplete ? .green : .orange)
                }
                ProgressView(value: dashboard.readingProgress)
                    .tint(dashboard.isReadingRoutineComplete ? .green : .orange)
            }
            .padding(.vertical, 4)

            LabeledContent("Opérations de nettoyage dues") {
                Text("\(dashboard.dueCleaningTasks.count)")
                    .monospacedDigit()
            }

            LabeledContent("Produits entamés") {
                Text("\(dashboard.openProductsCount)")
                    .monospacedDigit()
            }

            if let rate = dashboard.complianceRate() {
                LabeledContent("Conformité sur 30 jours") {
                    Text(rate.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .foregroundStyle(rate >= 0.95 ? .green : .orange)
                }
            }

            if let name = preferences?.operatorName, !name.isEmpty {
                LabeledContent("Opérateur", value: name)
            }
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
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: alert.systemImage)
                            .font(.title3)
                            .foregroundStyle(color(for: alert.severity))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.title)
                                .font(.subheadline.weight(.semibold))
                            Text(alert.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Relevés attendus

    @ViewBuilder
    private var pendingReadingsSection: some View {
        if !dashboard.pendingReadings.isEmpty {
            Section("Relevés à saisir") {
                ForEach(dashboard.pendingReadings) { pending in
                    HStack {
                        Label(pending.equipment.name, systemImage: pending.equipment.type.systemImage)
                        Spacer()
                        Label(pending.moment.label, systemImage: pending.moment.systemImage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Diagnostic

    private var diagnosticSection: some View {
        Section("Diagnostic du schéma") {
            diagnosticRow(label: "Établissements", value: establishments.count)
            diagnosticRow(label: "Équipements", value: equipments.count)
            diagnosticRow(label: "Relevés de température", value: totalReadings)
            diagnosticRow(label: "Produits tracés", value: products.count)
            diagnosticRow(label: "Contrôles à réception", value: deliveries.count)
            diagnosticRow(label: "Tâches de nettoyage", value: cleaningTasks.count)
        }
    }

    private var equipmentsSection: some View {
        Section("Équipements") {
            ForEach(equipments) { equipment in
                VStack(alignment: .leading, spacing: 4) {
                    Label(equipment.name, systemImage: equipment.type.systemImage)
                        .font(.headline)
                    Text("\(equipment.type.label) — \(equipment.formattedRange)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(latestReadingSummary(for: equipment))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private var productsSection: some View {
        if !products.isEmpty {
            Section("Produits entamés") {
                ForEach(products) { product in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name)
                            Text(product.storage.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(product.remainingLabel())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(color(for: product.urgency()))
                    }
                }
            }
        }
    }

    // MARK: - Sous-vues

    private func diagnosticRow(label: String, value: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)")
                .monospacedDigit()
                .foregroundStyle(value > 0 ? .green : .secondary)
        }
    }

    // MARK: - Helpers

    private var totalReadings: Int {
        equipments.reduce(0) { $0 + $1.readings.count }
    }

    private func latestReadingSummary(for equipment: Equipment) -> String {
        guard let reading = equipment.latestReading else { return "Aucun relevé enregistré" }
        let status = reading.isCompliant ? "conforme" : "NON CONFORME"
        return "Dernier relevé : \(reading.formattedValue) — \(status)"
    }

    private func color(for urgency: ExpiryUrgency) -> Color {
        switch urgency {
        case .safe:     .green
        case .warning:  .yellow
        case .critical: .orange
        case .expired:  .red
        }
    }

    private func color(for severity: DashboardAlert.Severity) -> Color {
        switch severity {
        case .info:     .blue
        case .warning:  .orange
        case .critical: .red
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(AppSchema.preview)
        .environment(UserPreferences.shared)
        .environment(NotificationService.shared)
}
