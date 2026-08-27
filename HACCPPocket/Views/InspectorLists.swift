//
//  InspectorLists.swift
//  HACCPPocket
//
//  Les listes remises au contrôleur : uniquement de la lecture.
//
//  Elles répètent volontairement une partie de ce qu'affichent les écrans
//  normaux. C'est le prix de la garantie : une vue de consultation qui
//  réutiliserait les composants d'édition finirait tôt ou tard par en hériter
//  un bouton.
//

import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Ligne générique

/// Une ligne de registre en lecture seule : un intitulé, une date, un détail
/// et un état.
private struct InspectorRow: View {

    let title: String
    let date: Date
    let detail: String
    var badge: String?
    var badgeColor: Color = .green

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(AppFormatters.dateAndTime(date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if let badge {
                StatusBadge(text: badge, color: badgeColor)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Températures

struct InspectorTemperatureList: View {

    @Query(sort: \TemperatureReading.recordedAt, order: .reverse)
    private var readings: [TemperatureReading]

    var body: some View {
        List(readings) { reading in
            InspectorRow(
                title: reading.equipment?.name ?? "Enceinte supprimée",
                date: reading.recordedAt,
                detail: detail(for: reading),
                badge: reading.isCompliant ? "Conforme" : "Écart",
                badgeColor: reading.isCompliant ? .green : .red
            )
        }
        .navigationTitle("Températures")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if readings.isEmpty { emptyOverlay } }
    }

    private func detail(for reading: TemperatureReading) -> String {
        var parts = [
            "\(reading.formattedValue) · plage \(AppFormatters.range(reading.appliedRange))",
            reading.moment.label
        ]
        if !reading.operatorName.isEmpty { parts.append(reading.operatorName) }
        if !reading.correctiveAction.isEmpty {
            parts.append("Action : \(reading.correctiveAction)")
        }
        return parts.joined(separator: " · ")
    }

    private var emptyOverlay: some View {
        ContentUnavailableView("Aucun relevé", systemImage: "thermometer.medium")
    }
}

// MARK: - Produits

struct InspectorProductList: View {

    @Query(sort: \TrackedProduct.openedAt, order: .reverse)
    private var products: [TrackedProduct]

    var body: some View {
        List(products) { product in
            InspectorRow(
                title: product.name,
                date: product.openedAt,
                detail: detail(for: product),
                badge: product.status.label,
                badgeColor: product.status == .discarded ? .orange : .green
            )
        }
        .navigationTitle("Produits entamés")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if products.isEmpty {
                ContentUnavailableView("Aucun produit", systemImage: "shippingbox")
            }
        }
    }

    private func detail(for product: TrackedProduct) -> String {
        var parts = ["Limite le \(AppFormatters.shortDate(product.effectiveLimitDate))"]
        if !product.batchNumber.isEmpty { parts.append("lot \(product.batchNumber)") }
        if !product.supplier.isEmpty { parts.append(product.supplier) }
        if !product.discardReason.isEmpty { parts.append("Motif : \(product.discardReason)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Réceptions

struct InspectorDeliveryList: View {

    @Query(sort: \DeliveryCheck.receivedAt, order: .reverse)
    private var deliveries: [DeliveryCheck]

    var body: some View {
        List(deliveries) { delivery in
            InspectorRow(
                title: delivery.supplierName,
                date: delivery.receivedAt,
                detail: detail(for: delivery),
                badge: delivery.decision.label,
                badgeColor: delivery.isFullyCompliant ? .green : .orange
            )
        }
        .navigationTitle("Réceptions")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if deliveries.isEmpty {
                ContentUnavailableView("Aucun contrôle", systemImage: "truck.box")
            }
        }
    }

    private func detail(for delivery: DeliveryCheck) -> String {
        var parts: [String] = []
        if !delivery.productLabel.isEmpty { parts.append(delivery.productLabel) }
        parts.append(delivery.formattedTemperature)
        if !delivery.anomalies.isEmpty {
            parts.append("Anomalies : \(delivery.anomalies.joined(separator: ", "))")
        }
        if !delivery.reason.isEmpty { parts.append(delivery.reason) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Nettoyage

struct InspectorCleaningList: View {

    @Query(sort: \CleaningRecord.completedAt, order: .reverse)
    private var records: [CleaningRecord]

    var body: some View {
        List(records) { record in
            VStack(alignment: .leading, spacing: 6) {
                InspectorRow(
                    title: record.taskTitle,
                    date: record.completedAt,
                    detail: detail(for: record),
                    badge: record.operatorName.isEmpty ? "Sans opérateur" : nil,
                    badgeColor: .orange
                )

                if let signature = record.signatureData {
                    SignatureView(data: signature, height: 50)
                }
            }
        }
        .navigationTitle("Nettoyage")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if records.isEmpty {
                ContentUnavailableView("Aucune opération", systemImage: "sparkles")
            }
        }
    }

    private func detail(for record: CleaningRecord) -> String {
        var parts: [String] = []
        if !record.operatorName.isEmpty { parts.append(record.operatorName) }
        if !record.productUsed.isEmpty { parts.append(record.productUsed) }
        if !record.comment.isEmpty { parts.append(record.comment) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Process thermiques

struct InspectorThermalList: View {

    @Query(sort: \ThermalProcessRecord.startedAt, order: .reverse)
    private var records: [ThermalProcessRecord]

    var body: some View {
        List(records) { record in
            InspectorRow(
                title: record.productName,
                date: record.startedAt,
                detail: detail(for: record),
                badge: record.isFinished ? (record.isCompliant ? "Conforme" : "Non conforme") : "En cours",
                badgeColor: record.isFinished ? (record.isCompliant ? .green : .red) : .orange
            )
        }
        .navigationTitle("Process thermiques")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if records.isEmpty {
                ContentUnavailableView("Aucune opération", systemImage: "thermometer.variable")
            }
        }
    }

    private func detail(for record: ThermalProcessRecord) -> String {
        var parts = [record.kind.label]
        if record.isFinished { parts.append("durée \(record.formattedDuration())") }
        parts.append("départ \(AppFormatters.temperature(record.startTemperature))")
        if let end = record.endTemperature {
            parts.append("fin \(AppFormatters.temperature(end))")
        }
        if let reason = record.failureReason { parts.append(reason) }
        if !record.correctiveAction.isEmpty { parts.append("Action : \(record.correctiveAction)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Huiles

struct InspectorOilList: View {

    @Query(sort: \OilCheckRecord.checkedAt, order: .reverse)
    private var checks: [OilCheckRecord]

    var body: some View {
        List(checks) { check in
            InspectorRow(
                title: check.fryerName,
                date: check.checkedAt,
                detail: "\(check.measurementLabel) · \(check.appearance.label) · \(check.action.label)",
                badge: check.isCompliant ? "Conforme" : "Non conforme",
                badgeColor: check.isCompliant ? .green : .red
            )
        }
        .navigationTitle("Bains de friture")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if checks.isEmpty {
                ContentUnavailableView("Aucun contrôle", systemImage: "drop.triangle")
            }
        }
    }
}

// MARK: - Carte

struct InspectorMenuList: View {

    @Query(sort: [SortDescriptor(\Dish.sortIndex), SortDescriptor(\Dish.name)])
    private var dishes: [Dish]

    var body: some View {
        List(dishes) { dish in
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(dish.displayName)
                        .font(.subheadline.weight(.medium))
                    if !dish.isAvailable {
                        StatusBadge(text: "Retiré", color: .secondary)
                    }
                    Spacer(minLength: 0)
                }

                Text(dish.category.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if dish.needsAllergenReview {
                    Label("Fiche allergènes non renseignée", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Allergènes : \(dish.allergenSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Carte et allergènes")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if dishes.isEmpty {
                ContentUnavailableView("Carte vide", systemImage: "fork.knife")
            }
        }
    }
}

// MARK: - Documents

struct InspectorDocumentList: View {

    @Query(sort: \RegulatoryDocument.issuedAt, order: .reverse)
    private var documents: [RegulatoryDocument]

    var body: some View {
        List(documents) { document in
            NavigationLink {
                InspectorDocumentDetail(document: document)
            } label: {
                InspectorRow(
                    title: document.displayName,
                    date: document.issuedAt,
                    detail: document.issuer,
                    badge: document.hasFile ? nil : "Sans pièce",
                    badgeColor: .orange
                )
            }
        }
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if documents.isEmpty {
                ContentUnavailableView("Aucun document", systemImage: "folder")
            }
        }
    }
}

struct InspectorDocumentDetail: View {

    let document: RegulatoryDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.gutter) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.displayName)
                        .font(.title3.weight(.semibold))
                    Text(document.category.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !document.issuer.isEmpty {
                        Text(document.issuer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Établi le \(AppFormatters.shortDate(document.issuedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .cardSurface()

                #if canImport(UIKit)
                if let data = document.fileData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
                } else {
                    Label("Aucune pièce jointe", systemImage: "doc.badge.ellipsis")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(30)
                        .cardSurface()
                }
                #endif
            }
            .padding(16)
            .readableWidth()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Document")
        .navigationBarTitleDisplayMode(.inline)
    }
}
