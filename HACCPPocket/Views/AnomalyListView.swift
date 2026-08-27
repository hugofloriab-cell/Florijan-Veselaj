//
//  AnomalyListView.swift
//  HACCPPocket
//
//  Toutes les anomalies en cours, au même endroit.
//
//  Un écart de température sans action corrective écrite est un dossier
//  incomplet. Le tableau de bord le signale, mais il ne dit pas *lesquels* :
//  cette page les liste un par un, et chaque ligne ouvre directement le
//  relevé à corriger. Deux appuis entre le constat et la correction.
//

import SwiftUI
import SwiftData

struct AnomalyListView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TemperatureReading.recordedAt, order: .reverse)
    private var readings: [TemperatureReading]

    @Query(sort: \ThermalProcessRecord.startedAt, order: .reverse)
    private var thermalRecords: [ThermalProcessRecord]

    @Query(sort: \OilCheckRecord.checkedAt, order: .reverse)
    private var oilChecks: [OilCheckRecord]

    @Query(sort: \DeliveryCheck.receivedAt, order: .reverse)
    private var deliveries: [DeliveryCheck]

    @Query(sort: \TrackedProduct.openedAt, order: .reverse)
    private var products: [TrackedProduct]

    /// Relevé ouvert pour correction.
    @State private var editedReading: TemperatureReading?
    @State private var editedDelivery: DeliveryCheck?
    @State private var editedProduct: TrackedProduct?

    // MARK: - Regroupement

    /// Écarts de température sans action corrective : les plus urgents,
    /// parce qu'ils se corrigent en une phrase et qu'ils sont les premiers
    /// que lira un contrôleur.
    private var undocumentedReadings: [TemperatureReading] {
        readings.filter { !$0.isCompliant && $0.needsCorrectiveAction }
    }

    /// Écarts déjà documentés, gardés visibles quelques jours : ils prouvent
    /// que le système fonctionne.
    private var documentedReadings: [TemperatureReading] {
        let limit = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        return readings.filter { !$0.isCompliant && !$0.needsCorrectiveAction && $0.recordedAt >= limit }
    }

    private var failedThermal: [ThermalProcessRecord] {
        thermalRecords.filter { $0.isFinished && !$0.isCompliant }
    }

    private var failedOil: [OilCheckRecord] {
        oilChecks.filter { !$0.isCompliant }
    }

    private var refusedDeliveries: [DeliveryCheck] {
        deliveries.filter { !$0.isFullyCompliant }
    }

    private var expiredProducts: [TrackedProduct] {
        products.filter { $0.status == .inUse && $0.urgency() == .expired }
    }

    private var totalOpen: Int {
        undocumentedReadings.count + failedThermal.count + failedOil.count + expiredProducts.count
    }

    var body: some View {
        List {
            if totalOpen == 0 {
                Section {
                    ContentUnavailableView {
                        Label("Aucune anomalie en cours", systemImage: "checkmark.seal.fill")
                    } description: {
                        Text("Rien à corriger. C'est exactement ce qu'un contrôleur veut voir.")
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if !undocumentedReadings.isEmpty {
                Section {
                    ForEach(undocumentedReadings) { reading in
                        Button {
                            editedReading = reading
                        } label: {
                            readingRow(reading, isDocumented: false)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Écarts sans action corrective")
                } footer: {
                    Text("Appuyez sur une ligne pour ouvrir le relevé et écrire ce qui a été fait. L'application vous guidera.")
                }
            }

            if !expiredProducts.isEmpty {
                Section("Produits à retirer") {
                    ForEach(expiredProducts) { product in
                        Button {
                            editedProduct = product
                        } label: {
                            row(
                                title: product.name,
                                subtitle: "Limite dépassée le \(AppFormatters.shortDate(product.effectiveLimitDate))",
                                systemImage: "trash.circle.fill",
                                tint: .red
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !failedThermal.isEmpty {
                Section("Process thermiques non conformes") {
                    ForEach(failedThermal) { record in
                        row(
                            title: record.productName,
                            subtitle: record.failureReason ?? record.kind.label,
                            systemImage: "thermometer.variable",
                            tint: .red,
                            date: record.startedAt
                        )
                    }
                }
            }

            if !failedOil.isEmpty {
                Section("Bains de friture non conformes") {
                    ForEach(failedOil) { check in
                        row(
                            title: check.fryerName,
                            subtitle: "\(check.formattedPolarCompounds) · \(check.action.label)",
                            systemImage: "drop.triangle.fill",
                            tint: .red,
                            date: check.checkedAt
                        )
                    }
                }
            }

            if !refusedDeliveries.isEmpty {
                Section {
                    ForEach(refusedDeliveries.prefix(20)) { delivery in
                        Button {
                            editedDelivery = delivery
                        } label: {
                            row(
                                title: delivery.supplierName,
                                subtitle: delivery.anomalies.joined(separator: ", "),
                                systemImage: "truck.box.badge.clock",
                                tint: .orange,
                                date: delivery.receivedAt
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Réceptions avec anomalie")
                } footer: {
                    Text("Conservées pour mémoire : une réception refusée est une décision correcte, pas un incident à corriger.")
                }
            }

            if !documentedReadings.isEmpty {
                Section {
                    ForEach(documentedReadings) { reading in
                        Button {
                            editedReading = reading
                        } label: {
                            readingRow(reading, isDocumented: true)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Écarts traités, sept derniers jours")
                } footer: {
                    Text("Un écart constaté puis traité prouve que la surveillance fonctionne. C'est l'absence d'écart pendant des mois qui intrigue un contrôleur.")
                }
            }
        }
        .navigationTitle("Anomalies")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editedReading) { reading in
            GuidedTemperatureInputView(
                equipment: reading.equipment ?? Equipment(name: "Enceinte supprimée", type: .positiveCold),
                moment: reading.moment,
                reading: reading,
                context: modelContext
            )
        }
        .sheet(item: $editedDelivery) { delivery in
            DeliveryFormView(check: delivery, context: modelContext)
        }
        .sheet(item: $editedProduct) { product in
            ProductFormView(product: product, context: modelContext)
        }
    }

    // MARK: - Lignes

    private func readingRow(_ reading: TemperatureReading, isDocumented: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RowIcon(
                systemImage: isDocumented ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                tint: isDocumented ? .green : .red
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(reading.equipment?.name ?? "Enceinte supprimée")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Text("\(reading.formattedValue) · plage \(AppFormatters.range(reading.appliedRange)) · \(AppFormatters.dateAndTime(reading.recordedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isDocumented {
                    Text(reading.correctiveAction)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .lineLimit(2)
                } else {
                    Label("Action corrective à écrire", systemImage: "square.and.pencil")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func row(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        date: Date? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RowIcon(systemImage: systemImage, tint: tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let date {
                    Text(AppFormatters.dateAndTime(date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
