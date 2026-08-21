//
//  ContentView.swift
//  HACCPPocket
//
//  ⚠️ ÉCRAN TEMPORAIRE (Step A uniquement).
//  Il sert à vérifier que le schéma SwiftData se charge, que l'amorçage
//  fonctionne et que les relations sont bien câblées. Il sera intégralement
//  remplacé par la vraie navigation à racine au Step C.
//

import SwiftUI
import SwiftData

struct ContentView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Equipment.sortIndex) private var equipments: [Equipment]
    @Query(sort: \CleaningTask.sortIndex) private var cleaningTasks: [CleaningTask]
    @Query(sort: \TrackedProduct.secondaryLimitDate) private var products: [TrackedProduct]
    @Query(sort: \DeliveryCheck.receivedAt, order: .reverse) private var deliveries: [DeliveryCheck]
    @Query private var establishments: [Establishment]

    var body: some View {
        NavigationStack {
            List {
                Section("Diagnostic du schéma") {
                    diagnosticRow(label: "Établissements", value: establishments.count)
                    diagnosticRow(label: "Équipements", value: equipments.count)
                    diagnosticRow(label: "Relevés de température", value: totalReadings)
                    diagnosticRow(label: "Produits tracés", value: products.count)
                    diagnosticRow(label: "Contrôles à réception", value: deliveries.count)
                    diagnosticRow(label: "Tâches de nettoyage", value: cleaningTasks.count)
                }

                Section("Équipements") {
                    if equipments.isEmpty {
                        ContentUnavailableView(
                            "Aucun équipement",
                            systemImage: "refrigerator",
                            description: Text("L'amorçage n'a rien inséré.")
                        )
                    } else {
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

                Section("Produits entamés") {
                    if products.isEmpty {
                        Text("Aucun produit tracé pour l'instant.")
                            .foregroundStyle(.secondary)
                    } else {
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

                Section("Plan de nettoyage") {
                    ForEach(cleaningTasks) { task in
                        HStack {
                            Label(task.title, systemImage: task.frequency.systemImage)
                            Spacer()
                            Text(task.frequency.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("HACCP Pocket")
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
}

#Preview {
    ContentView()
        .modelContainer(AppSchema.preview)
}
