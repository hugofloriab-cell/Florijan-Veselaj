//
//  CleaningProductView.swift
//  HACCPPocket
//
//  Fiches techniques des produits d'entretien.
//

import SwiftUI
import SwiftData
import PhotosUI

#if canImport(UIKit)
import UIKit
#endif

struct CleaningProductListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \CleaningProduct.name)
    private var products: [CleaningProduct]

    @State private var isCreating = false
    @State private var editedProduct: CleaningProduct?
    @State private var showsPaywall = false

    private var active: [CleaningProduct] { products.filter(\.isActive) }
    private var archived: [CleaningProduct] { products.filter { !$0.isActive } }
    private var incompleteCount: Int { active.filter(\.isIncomplete).count }

    var body: some View {
        List {
            Section { ProtocolLink(procedure: .cleaning) }

            if products.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Aucune fiche produit", systemImage: "bubbles.and.sparkles")
                    } description: {
                        Text("Un désinfectant mal dilué ou essuyé trop tôt ne désinfecte pas. Le dosage et le temps de contact sont écrits en petit sur un bidon rangé sous l'évier — mettez-les ici.")
                    } actions: {
                        Button("Ajouter un produit") { create() }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if incompleteCount > 0 {
                Section {
                    Label(
                        "\(incompleteCount) fiche(s) sans dosage ou sans temps de contact. C'est pourtant exactement l'information qu'on vient y chercher.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !active.isEmpty {
                Section("Produits utilisés") {
                    ForEach(active) { product in row(product) }
                }
            }

            if !archived.isEmpty {
                Section("Retirés") {
                    ForEach(archived) { product in row(product) }
                }
            }
        }
        .navigationTitle("Produits d'entretien")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { create() } label: {
                    Label("Ajouter un produit", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            CleaningProductEditorView(product: nil, context: modelContext)
        }
        .sheet(item: $editedProduct) { product in
            CleaningProductEditorView(product: product, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }

    private func row(_ product: CleaningProduct) -> some View {
        Button {
            editedProduct = product
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(
                    systemImage: product.kind.systemImage,
                    tint: product.isActive ? (product.isIncomplete ? .orange : .brand) : .secondary
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(product.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(product.isActive ? Color.primary : Color.secondary)

                    Text(product.kind.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        detailChip("Dilution", value: product.dilution.isEmpty ? "—" : product.dilution)
                        if product.kind.requiresContactTime {
                            detailChip("Contact", value: product.formattedContactTime)
                        }
                    }
                }

                Spacer(minLength: 8)

                if product.hasSafetyDataSheet {
                    Image(systemName: "doc.text.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(product) } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private func detailChip(_ title: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func create() {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        isCreating = true
    }

    private func delete(_ product: CleaningProduct) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        modelContext.delete(product)
        try? modelContext.save()
    }
}

// MARK: - Éditeur

struct CleaningProductEditorView: View {

    @Environment(\.dismiss) private var dismiss

    private let product: CleaningProduct?
    private let context: ModelContext

    @State private var name: String
    @State private var supplier: String
    @State private var kind: CleaningProductKind
    @State private var dilution: String
    @State private var contactMinutes: Int
    @State private var contactSeconds: Int
    @State private var requiresRinsing: Bool
    @State private var usage: String
    @State private var hazards: String
    @State private var standard: String
    @State private var isActive: Bool
    @State private var comment: String
    @State private var safetyDataSheet: Data?
    @State private var sheetItem: PhotosPickerItem?

    init(product: CleaningProduct?, context: ModelContext) {
        self.product = product
        self.context = context

        let total = product?.contactTimeSeconds ?? 0

        _name = State(initialValue: product?.name ?? "")
        _supplier = State(initialValue: product?.supplier ?? "")
        _kind = State(initialValue: product?.kind ?? .disinfectant)
        _dilution = State(initialValue: product?.dilution ?? "")
        _contactMinutes = State(initialValue: total / 60)
        _contactSeconds = State(initialValue: total % 60)
        _requiresRinsing = State(initialValue: product?.requiresRinsing ?? true)
        _usage = State(initialValue: product?.usage ?? "")
        _hazards = State(initialValue: product?.hazards ?? "")
        _standard = State(initialValue: product?.standard ?? "")
        _isActive = State(initialValue: product?.isActive ?? true)
        _comment = State(initialValue: product?.comment ?? "")
        _safetyDataSheet = State(initialValue: product?.safetyDataSheet)
    }

    private var totalContactSeconds: Int {
        contactMinutes * 60 + contactSeconds
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Produit") {
                    TextField("Nom commercial", text: $name)
                    TextField("Fournisseur", text: $supplier)

                    Picker("Nature", selection: $kind) {
                        ForEach(CleaningProductKind.allCases) { kind in
                            Label(kind.label, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                }

                Section {
                    TextField("Dilution (ex. 2 %, 20 mL/L)", text: $dilution)

                    if kind.requiresContactTime {
                        Stepper("Temps de contact : \(contactMinutes) min", value: $contactMinutes, in: 0...60)
                        Stepper("… et \(contactSeconds) s", value: $contactSeconds, in: 0...59, step: 5)
                    }

                    Toggle("Rinçage obligatoire", isOn: $requiresRinsing)
                } header: {
                    Text("Mode d'emploi")
                } footer: {
                    Text(kind.requiresContactTime
                         ? "Le temps de contact est la durée pendant laquelle le produit doit rester sur la surface avant d'être essuyé ou rincé. L'essuyer avant revient à ne pas désinfecter."
                         : "Recopiez la dilution exacte indiquée sur le bidon.")
                }

                Section("Emploi") {
                    TextField("Surfaces et zones concernées", text: $usage, axis: .vertical)
                        .lineLimit(1...4)
                    TextField("Norme d'efficacité (EN 1276, EN 13697…)", text: $standard)
                }

                Section {
                    TextField("Mentions de danger de l'étiquette", text: $hazards, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("Sécurité")
                } footer: {
                    Text("Recopiez les mentions H et P figurant sur l'emballage : c'est ce que votre personnel doit connaître avant de manipuler le produit.")
                }

                safetySheetSection

                Section {
                    Toggle("Produit utilisé actuellement", isOn: $isActive)
                    TextField("Commentaire", text: $comment, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle(product == nil ? "Nouveau produit" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var safetySheetSection: some View {
        Section {
            #if canImport(UIKit)
            if let safetyDataSheet, let image = UIImage(data: safetyDataSheet) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button(role: .destructive) {
                    self.safetyDataSheet = nil
                } label: {
                    Label("Retirer la fiche", systemImage: "trash")
                }
            }
            #endif

            PhotosPicker(selection: $sheetItem, matching: .images) {
                Label(
                    safetyDataSheet == nil ? "Photographier la fiche de sécurité" : "Remplacer la fiche",
                    systemImage: "doc.viewfinder"
                )
            }
        } header: {
            Text("Fiche de données de sécurité")
        } footer: {
            Text("L'employeur doit la tenir à disposition du personnel. La garder ici évite d'aller la chercher en cas d'accident — le moment où on en a le plus besoin.")
        }
        .onChange(of: sheetItem) { _, item in
            Task { await loadSheet(item) }
        }
    }

    private func loadSheet(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            safetyDataSheet = data
        }
    }

    private func save() {
        let target = product ?? CleaningProduct()

        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.supplier = supplier
        target.kind = kind
        target.dilution = dilution
        target.contactTimeSeconds = kind.requiresContactTime ? totalContactSeconds : 0
        target.requiresRinsing = requiresRinsing
        target.usage = usage
        target.hazards = hazards
        target.standard = standard
        target.safetyDataSheet = safetyDataSheet
        target.isActive = isActive
        target.comment = comment
        target.touch()

        if product == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}
