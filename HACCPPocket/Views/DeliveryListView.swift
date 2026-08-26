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
    @State private var deliveryPendingDeletion: DeliveryCheck?

    var body: some View {
        List {
            Section { ProtocolLink(procedure: .delivery) }

            ForEach(deliveries) { delivery in
                Button {
                    editedDelivery = delivery
                } label: {
                    row(for: delivery)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deliveryPendingDeletion = delivery
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                }
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
        .confirmationDialog(
            "Supprimer ce contrôle ?",
            isPresented: Binding(
                get: { deliveryPendingDeletion != nil },
                set: { if !$0 { deliveryPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let delivery = deliveryPendingDeletion {
                    modelContext.delete(delivery)
                    try? modelContext.save()
                }
                deliveryPendingDeletion = nil
            }
            Button("Annuler", role: .cancel) { deliveryPendingDeletion = nil }
        } message: {
            Text("À réserver à une saisie erronée : un contrôle réel doit rester dans le registre.")
        }
        .sheet(item: $editedDelivery) { delivery in
            DeliveryFormView(check: delivery, context: modelContext)
        }
    }

    private func row(for delivery: DeliveryCheck) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(
                    systemImage: delivery.decision.systemImage,
                    tint: delivery.decision == .accepted ? .green : .red
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(delivery.supplierName)
                        .font(.subheadline.weight(.semibold))
                    if !delivery.productLabel.isEmpty {
                        Text(delivery.productLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Text(AppFormatters.shortDate(delivery.receivedAt))
                        Text(delivery.formattedTemperature)
                            .foregroundStyle(delivery.isTemperatureCompliant ? Color.secondary : Color.red)
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                StatusBadge(
                    text: delivery.decision.label,
                    color: delivery.decision == .accepted ? .green : .red
                )
            }

            if !delivery.anomalies.isEmpty {
                Text(delivery.anomalies.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}
