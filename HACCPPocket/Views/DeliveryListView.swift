//
//  DeliveryListView.swift
//  HACCPPocket
//
//  Registre des contrôles à réception : premier maillon du plan de maîtrise
//  sanitaire, et le premier document réclamé lors d'un contrôle.
//

import SwiftUI
import SwiftData

struct DeliveryListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \DeliveryCheck.receivedAt, order: .reverse) private var deliveries: [DeliveryCheck]

    @State private var editedDelivery: DeliveryCheck?
    @State private var isCreating = false
    @State private var showsPaywall = false

    var body: some View {
        List {
            ForEach(deliveries) { delivery in
                Button {
                    editedDelivery = delivery
                } label: {
                    row(for: delivery)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Réception")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if subscription.canWrite {
                        isCreating = true
                    } else {
                        showsPaywall = true
                    }
                } label: {
                    Label("Nouveau contrôle", systemImage: "plus")
                }
            }
        }
        .overlay {
            if deliveries.isEmpty {
                ContentUnavailableView {
                    Label("Aucun contrôle", systemImage: "shippingbox")
                } description: {
                    Text("Enregistrez la température et l'état de chaque livraison à son arrivée.")
                } actions: {
                    Button("Nouveau contrôle") { isCreating = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            DeliveryFormView(context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
        }
        .sheet(item: $editedDelivery) { delivery in
            DeliveryFormView(check: delivery, context: modelContext)
        }
    }

    private func row(for delivery: DeliveryCheck) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(delivery.supplierName)
                        .font(.headline)
                    if !delivery.productLabel.isEmpty {
                        Text(delivery.productLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                StatusBadge(
                    text: delivery.decision.label,
                    color: delivery.decision == .accepted ? .green : .red,
                    systemImage: delivery.decision.systemImage
                )
            }

            HStack(spacing: 10) {
                Label(AppFormatters.shortDate(delivery.receivedAt), systemImage: "calendar")
                Label(delivery.formattedTemperature, systemImage: "thermometer.medium")
                    .foregroundStyle(delivery.isTemperatureCompliant ? Color.secondary : Color.red)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !delivery.anomalies.isEmpty {
                Text(delivery.anomalies.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}
