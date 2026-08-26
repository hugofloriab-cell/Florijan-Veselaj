//
//  ProductRecallView.swift
//  HACCPPocket
//
//  Registre des retraits et rappels.
//

import SwiftUI
import SwiftData
import PhotosUI

#if canImport(UIKit)
import UIKit
#endif

struct ProductRecallListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \ProductRecall.noticedAt, order: .reverse)
    private var recalls: [ProductRecall]

    @State private var isCreating = false
    @State private var editedRecall: ProductRecall?
    @State private var showsPaywall = false

    private var open: [ProductRecall] { recalls.filter { !$0.isClosed } }
    private var closed: [ProductRecall] { recalls.filter(\.isClosed) }

    var body: some View {
        List {
            Section { ProtocolLink(procedure: .productRecall) }

            if recalls.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Aucune alerte enregistrée", systemImage: "exclamationmark.octagon")
                    } description: {
                        Text("Le jour où un fournisseur signale un lot contaminé, les premières heures comptent. Ce registre garde la trace de ce qui a été fait, et quand.")
                    } actions: {
                        Button("Enregistrer une alerte") { create() }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    Label(
                        "Les alertes publiques sont publiées sur RappelConso, le site du gouvernement. L'application fonctionne hors ligne et ne peut pas le consulter à votre place : prenez l'habitude d'y jeter un œil.",
                        systemImage: "globe"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !open.isEmpty {
                Section {
                    ForEach(open) { recall in row(recall) }
                } header: {
                    Text("En cours")
                } footer: {
                    Text("Une alerte reste ouverte tant que toutes les actions ne sont pas faites.")
                }
            }

            if !closed.isEmpty {
                Section("Clôturées") {
                    ForEach(closed) { recall in row(recall) }
                }
            }
        }
        .navigationTitle("Retrait et rappel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { create() } label: {
                    Label("Enregistrer une alerte", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            ProductRecallEditorView(recall: nil, context: modelContext)
        }
        .sheet(item: $editedRecall) { recall in
            ProductRecallEditorView(recall: recall, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }

    private func row(_ recall: ProductRecall) -> some View {
        Button {
            editedRecall = recall
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 12) {
                    RowIcon(systemImage: recall.scope.systemImage, tint: tint(for: recall))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(recall.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        Text("\(recall.scope.label) · signalé le \(AppFormatters.dateAndTime(recall.noticedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !recall.affectedBatches.isEmpty {
                            Text("Lots : \(recall.affectedBatches)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    StatusBadge(text: recall.statusLabel, color: tint(for: recall))
                }

                // Ce qu'il reste à faire, énoncé comme des gestes.
                if !recall.isClosed && !recall.pendingSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(recall.pendingSteps, id: \.self) { step in
                            Label(step, systemImage: "circle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.leading, 44)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(recall) } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private func tint(for recall: ProductRecall) -> Color {
        if recall.isClosed { return .secondary }
        if recall.isComplete { return .green }
        return recall.scope.requiresPublicNotice ? .red : .orange
    }

    private func create() {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        isCreating = true
    }

    private func delete(_ recall: ProductRecall) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        modelContext.delete(recall)
        try? modelContext.save()
    }
}

// MARK: - Éditeur

struct ProductRecallEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferences.self) private var preferences

    private let recall: ProductRecall?
    private let context: ModelContext

    @State private var productName: String
    @State private var brand: String
    @State private var affectedBatches: String
    @State private var supplier: String
    @State private var noticeReference: String
    @State private var reason: String
    @State private var scope: RecallScope
    @State private var noticedAt: Date
    @State private var isIsolated: Bool
    @State private var isolatedAt: Date
    @State private var quantityHeld: String
    @State private var outcome: RecallOutcome
    @State private var wasServed: Bool
    @State private var customersInformed: Bool
    @State private var authorityInformed: Bool
    @State private var authorityInformedAt: Date
    @State private var operatorName: String
    @State private var notes: String
    @State private var isClosed: Bool
    @State private var proofData: Data?
    @State private var proofItem: PhotosPickerItem?

    init(recall: ProductRecall?, context: ModelContext) {
        self.recall = recall
        self.context = context

        _productName = State(initialValue: recall?.productName ?? "")
        _brand = State(initialValue: recall?.brand ?? "")
        _affectedBatches = State(initialValue: recall?.affectedBatches ?? "")
        _supplier = State(initialValue: recall?.supplier ?? "")
        _noticeReference = State(initialValue: recall?.noticeReference ?? "")
        _reason = State(initialValue: recall?.reason ?? "")
        _scope = State(initialValue: recall?.scope ?? .withdrawal)
        _noticedAt = State(initialValue: recall?.noticedAt ?? .now)
        _isIsolated = State(initialValue: recall?.isolatedAt != nil)
        _isolatedAt = State(initialValue: recall?.isolatedAt ?? .now)
        _quantityHeld = State(initialValue: recall?.quantityHeld ?? "")
        _outcome = State(initialValue: recall?.outcome ?? .pending)
        _wasServed = State(initialValue: recall?.wasServed ?? false)
        _customersInformed = State(initialValue: recall?.customersInformed ?? false)
        _authorityInformed = State(initialValue: recall?.authorityInformed ?? false)
        _authorityInformedAt = State(initialValue: recall?.authorityInformedAt ?? .now)
        _operatorName = State(initialValue: recall?.operatorName ?? "")
        _notes = State(initialValue: recall?.notes ?? "")
        _isClosed = State(initialValue: recall?.isClosed ?? false)
        _proofData = State(initialValue: recall?.proofData)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { ProtocolLink(procedure: .productRecall) }

                Section("Produit concerné") {
                    TextField("Désignation", text: $productName)
                    TextField("Marque", text: $brand)
                    TextField("Lots visés", text: $affectedBatches)
                    TextField("Fournisseur", text: $supplier)
                    TextField("Référence de l'avis (ou RappelConso)", text: $noticeReference)
                }

                Section {
                    TextField("Danger annoncé", text: $reason, axis: .vertical)
                        .lineLimit(1...4)
                    DatePicker("Alerte reçue le", selection: $noticedAt, in: ...Date.now)
                } header: {
                    Text("Alerte")
                } footer: {
                    Text("C'est de cette date que part le délai de réaction, et c'est le premier chiffre qu'un contrôleur regarde.")
                }

                Section {
                    Picker("Portée", selection: $scope) {
                        ForEach(RecallScope.allCases) { scope in
                            Label(scope.label, systemImage: scope.systemImage).tag(scope)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    Toggle("Le produit a déjà été servi", isOn: $wasServed)
                } header: {
                    Text("Portée")
                } footer: {
                    Text(scope.detail)
                }

                Section("Traitement du lot") {
                    Toggle("Lot isolé et étiqueté", isOn: $isIsolated)
                    if isIsolated {
                        DatePicker("Isolé le", selection: $isolatedAt, in: ...Date.now)
                    }

                    TextField("Quantité détenue", text: $quantityHeld)

                    Picker("Sort du lot", selection: $outcome) {
                        ForEach(RecallOutcome.allCases) { outcome in
                            Label(outcome.label, systemImage: outcome.systemImage).tag(outcome)
                        }
                    }
                }

                if wasServed {
                    Section {
                        Toggle("Consommateurs informés", isOn: $customersInformed)
                        Toggle("DDPP prévenue", isOn: $authorityInformed)
                        if authorityInformed {
                            DatePicker("Déclaré le", selection: $authorityInformedAt, in: ...Date.now)
                        }
                    } header: {
                        Label("Le produit a été servi", systemImage: "megaphone")
                    } footer: {
                        Text("Un exploitant qui a des raisons de penser qu'une denrée mise sur le marché est dangereuse doit engager immédiatement le retrait et en informer les autorités.")
                    }
                }

                proofSection

                Section("Détails") {
                    OperatorField(name: $operatorName)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                    Toggle("Alerte clôturée", isOn: $isClosed)
                }
            }
            .navigationTitle(recall == nil ? "Nouvelle alerte" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(productName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if operatorName.isEmpty { operatorName = preferences.operatorName }
            }
        }
    }

    @ViewBuilder
    private var proofSection: some View {
        Section {
            #if canImport(UIKit)
            if let proofData, let image = UIImage(data: proofData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button(role: .destructive) {
                    self.proofData = nil
                } label: {
                    Label("Retirer la preuve", systemImage: "trash")
                }
            }
            #endif

            PhotosPicker(selection: $proofItem, matching: .images) {
                Label(
                    proofData == nil ? "Photographier la preuve" : "Remplacer la preuve",
                    systemImage: "camera"
                )
            }
        } header: {
            Text("Preuve de destruction ou de retour")
        } footer: {
            Text("Bon de retour signé, bordereau de destruction, ou photo du produit rendu impropre à la consommation. Sans preuve, la destruction n'a pas eu lieu.")
        }
        .onChange(of: proofItem) { _, item in
            Task { await loadProof(item) }
        }
    }

    private func loadProof(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            proofData = data
        }
    }

    private func save() {
        let target = recall ?? ProductRecall()

        target.productName = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.brand = brand
        target.affectedBatches = affectedBatches
        target.supplier = supplier
        target.noticeReference = noticeReference
        target.reason = reason
        target.scope = scope
        target.noticedAt = noticedAt
        target.isolatedAt = isIsolated ? isolatedAt : nil
        target.quantityHeld = quantityHeld
        target.outcome = outcome
        target.wasServed = wasServed
        target.customersInformed = customersInformed
        target.authorityInformed = authorityInformed
        target.authorityInformedAt = authorityInformed ? authorityInformedAt : nil
        target.proofData = proofData
        target.operatorName = operatorName
        target.notes = notes
        target.closedAt = isClosed ? (target.closedAt ?? .now) : nil

        if recall == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}
