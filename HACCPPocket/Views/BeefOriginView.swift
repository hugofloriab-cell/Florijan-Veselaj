//
//  BeefOriginView.swift
//  HACCPPocket
//
//  Traçabilité de l'origine de la viande bovine.
//

import SwiftUI
import SwiftData
import PhotosUI

#if canImport(UIKit)
import UIKit
#endif

struct BeefOriginListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \BeefOriginRecord.receivedAt, order: .reverse)
    private var records: [BeefOriginRecord]

    @State private var isCreating = false
    @State private var editedRecord: BeefOriginRecord?
    @State private var showsPaywall = false

    private var incomplete: [BeefOriginRecord] { records.filter { !$0.isComplete } }

    var body: some View {
        List {
            Section { ProtocolLink(procedure: .beefOrigin) }

            if records.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Aucune origine enregistrée", systemImage: "text.badge.checkmark")
                    } description: {
                        Text("Servir de la viande bovine oblige à informer le client de son origine : pays de naissance, d'élevage et d'abattage. Ce registre garde la preuve, lot par lot.")
                    } actions: {
                        Button("Enregistrer un lot") { create() }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if !incomplete.isEmpty {
                Section {
                    ForEach(incomplete) { record in
                        row(record)
                    }
                } header: {
                    Text("À compléter")
                } footer: {
                    Text("Les trois pays doivent être connus pour pouvoir afficher quoi que ce soit en salle.")
                }
            }

            let complete = records.filter(\.isComplete)
            if !complete.isEmpty {
                Section("Lots tracés") {
                    ForEach(complete) { record in
                        row(record)
                    }
                }
            }
        }
        .navigationTitle("Origine viande bovine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { create() } label: {
                    Label("Enregistrer un lot", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            BeefOriginEditorView(record: nil, context: modelContext)
        }
        .sheet(item: $editedRecord) { record in
            BeefOriginEditorView(record: record, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }

    private func row(_ record: BeefOriginRecord) -> some View {
        Button {
            editedRecord = record
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(
                    systemImage: "fork.knife",
                    tint: record.isComplete ? .brand : .orange
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(record.displayMention)
                        .font(.caption)
                        .foregroundStyle(record.isComplete ? Color.secondary : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(AppFormatters.shortDate(record.receivedAt))\(record.batchNumber.isEmpty ? "" : " · lot \(record.batchNumber)")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                if record.hasLabelPhoto {
                    Image(systemName: "paperclip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(record) } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private func create() {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        isCreating = true
    }

    private func delete(_ record: BeefOriginRecord) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        modelContext.delete(record)
        try? modelContext.save()
    }
}

// MARK: - Éditeur

struct BeefOriginEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferences.self) private var preferences

    private let record: BeefOriginRecord?
    private let context: ModelContext

    @State private var cutName: String
    @State private var batchNumber: String
    @State private var supplier: String
    @State private var birthCountry: String
    @State private var rearingCountry: String
    @State private var slaughterCountry: String
    @State private var slaughterhouseApproval: String
    @State private var cuttingPlantApproval: String
    @State private var receivedAt: Date
    @State private var quantity: String
    @State private var operatorName: String
    @State private var comment: String
    @State private var labelPhotoData: Data?

    @State private var photoItem: PhotosPickerItem?

    /// Les pays les plus fréquents en France, pour éviter la saisie clavier.
    private let commonCountries = ["France", "Irlande", "Pologne", "Allemagne", "Pays-Bas", "Espagne", "Belgique", "Italie"]

    init(record: BeefOriginRecord?, context: ModelContext) {
        self.record = record
        self.context = context

        _cutName = State(initialValue: record?.cutName ?? "")
        _batchNumber = State(initialValue: record?.batchNumber ?? "")
        _supplier = State(initialValue: record?.supplier ?? "")
        _birthCountry = State(initialValue: record?.birthCountry ?? "")
        _rearingCountry = State(initialValue: record?.rearingCountry ?? "")
        _slaughterCountry = State(initialValue: record?.slaughterCountry ?? "")
        _slaughterhouseApproval = State(initialValue: record?.slaughterhouseApproval ?? "")
        _cuttingPlantApproval = State(initialValue: record?.cuttingPlantApproval ?? "")
        _receivedAt = State(initialValue: record?.receivedAt ?? .now)
        _quantity = State(initialValue: record?.quantity ?? "")
        _operatorName = State(initialValue: record?.operatorName ?? "")
        _comment = State(initialValue: record?.comment ?? "")
        _labelPhotoData = State(initialValue: record?.labelPhotoData)
    }

    private var isComplete: Bool {
        ![birthCountry, rearingCountry, slaughterCountry]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains("")
    }

    private var mention: String {
        guard isComplete else { return "Renseignez les trois pays pour obtenir la mention." }
        let countries = [birthCountry, rearingCountry, slaughterCountry]
        if Set(countries.map { $0.lowercased() }).count == 1 {
            return "Origine : \(countries[0])"
        }
        return "Né en \(birthCountry), élevé en \(rearingCountry), abattu en \(slaughterCountry)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pièce") {
                    TextField("Désignation (entrecôte, haché…)", text: $cutName)
                    TextField("Numéro de lot", text: $batchNumber)
                    TextField("Fournisseur", text: $supplier)
                    TextField("Quantité (facultatif)", text: $quantity)
                    DatePicker("Réceptionné le", selection: $receivedAt, in: ...Date.now)
                }

                Section {
                    countryField("Pays de naissance", text: $birthCountry)
                    countryField("Pays d'élevage", text: $rearingCountry)
                    countryField("Pays d'abattage", text: $slaughterCountry)

                    Button {
                        // Le cas le plus courant en France : trois fois le
                        // même pays. Autant l'obtenir en un appui.
                        rearingCountry = birthCountry
                        slaughterCountry = birthCountry
                    } label: {
                        Label("Même pays pour les trois", systemImage: "equal.circle")
                    }
                    .disabled(birthCountry.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Origine")
                } footer: {
                    Text("Ces trois informations sont celles que le client a le droit de connaître. Elles figurent sur l'étiquette du fournisseur.")
                }

                Section {
                    Text(mention)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isComplete ? Color.brand : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Mention à afficher en salle")
                }

                Section("Agréments sanitaires") {
                    TextField("Abattoir", text: $slaughterhouseApproval)
                    TextField("Atelier de découpe", text: $cuttingPlantApproval)
                }

                photoSection

                Section("Détails") {
                    OperatorField(name: $operatorName)
                    TextField("Commentaire", text: $comment, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle(record == nil ? "Nouveau lot" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(cutName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if operatorName.isEmpty { operatorName = preferences.operatorName }
            }
        }
    }

    /// Champ libre doublé d'un menu : on tape rarement « Irlande » à la main
    /// quand on peut l'appuyer.
    private func countryField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            TextField("Pays", text: text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.words)

            Menu {
                ForEach(commonCountries, id: \.self) { country in
                    Button(country) { text.wrappedValue = country }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.brand)
            }
        }
    }

    @ViewBuilder
    private var photoSection: some View {
        Section {
            #if canImport(UIKit)
            if let labelPhotoData, let image = UIImage(data: labelPhotoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button(role: .destructive) {
                    self.labelPhotoData = nil
                } label: {
                    Label("Retirer la photo", systemImage: "trash")
                }
            }
            #endif

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(
                    labelPhotoData == nil ? "Photographier l'étiquette" : "Remplacer la photo",
                    systemImage: "camera"
                )
            }
        } header: {
            Text("Étiquette du fournisseur")
        } footer: {
            Text("C'est elle qui fait foi en cas de contrôle : la mention affichée en salle doit pouvoir être rattachée au document d'origine.")
        }
        .onChange(of: photoItem) { _, item in
            Task { await loadPhoto(item) }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            labelPhotoData = data
        }
    }

    private func save() {
        let target = record ?? BeefOriginRecord()

        target.cutName = cutName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.batchNumber = batchNumber
        target.supplier = supplier
        target.birthCountry = birthCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        target.rearingCountry = rearingCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        target.slaughterCountry = slaughterCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        target.slaughterhouseApproval = slaughterhouseApproval
        target.cuttingPlantApproval = cuttingPlantApproval
        target.receivedAt = receivedAt
        target.quantity = quantity
        target.labelPhotoData = labelPhotoData
        target.operatorName = operatorName
        target.comment = comment

        if record == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}
