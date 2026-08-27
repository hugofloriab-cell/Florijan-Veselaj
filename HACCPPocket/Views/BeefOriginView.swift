//
//  BeefOriginView.swift
//  HACCPPocket
//
//  Traçabilité de l'origine des viandes servies.
//
//  Le registre ne suit pas seulement le bœuf : depuis le décret n° 2022-65,
//  le porc, le mouton et la volaille sont visés de la même façon. Chaque
//  viande proposée à la carte y figure séparément — dix viandes au menu, dix
//  fiches — et l'écran produit le document daté à afficher en salle.
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
    @Environment(UserPreferences.self) private var preferences

    @Query(sort: \BeefOriginRecord.receivedAt, order: .reverse)
    private var records: [BeefOriginRecord]

    @Query private var establishments: [Establishment]

    @State private var isCreating = false
    @State private var editedRecord: BeefOriginRecord?
    @State private var showsPaywall = false
    @State private var sheetURL: URL?
    @State private var isPreparing = false
    @State private var errorMessage: String?

    private var onMenu: [BeefOriginRecord] { records.filter(\.isOnMenu) }
    private var offMenu: [BeefOriginRecord] { records.filter { !$0.isOnMenu } }
    private var incomplete: [BeefOriginRecord] { onMenu.filter { !$0.isComplete } }

    var body: some View {
        List {
            Section { ProtocolLink(procedure: .beefOrigin) }

            if records.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Aucune viande déclarée", systemImage: "text.badge.checkmark")
                    } description: {
                        Text("Toutes les viandes de votre carte doivent être listées avec leur origine : bovine, porcine, ovine et volaille depuis le décret de 2022. Listez-les ici, l'application produit le document à afficher.")
                    } actions: {
                        Button("Déclarer une viande") { create() }
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
                    Text("Les trois pays doivent être connus pour afficher quoi que ce soit. Une origine incomplète apparaîtra en rouge sur le document.")
                }
            }

            let complete = onMenu.filter(\.isComplete)
            if !complete.isEmpty {
                Section {
                    ForEach(complete) { record in
                        row(record)
                    }
                } header: {
                    Text("À la carte")
                }
            }

            if !offMenu.isEmpty {
                Section {
                    ForEach(offMenu) { record in
                        row(record)
                    }
                } header: {
                    Text("Retirées de la carte")
                } footer: {
                    Text("Conservées pour l'historique : elles ne figurent pas sur le document affiché.")
                }
            }

            if !onMenu.isEmpty {
                documentSection
            }
        }
        .navigationTitle("Origine des viandes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { create() } label: {
                    Label("Déclarer une viande", systemImage: "plus")
                }
            }
        }
        // Après toute modification, le document déjà préparé ne reflète plus
        // le registre. On l'oublie plutôt que de laisser imprimer une version
        // périmée : ce papier est affiché devant les clients.
        .sheet(isPresented: $isCreating, onDismiss: { sheetURL = nil }) {
            BeefOriginEditorView(record: nil, context: modelContext)
        }
        .sheet(item: $editedRecord, onDismiss: { sheetURL = nil }) { record in
            BeefOriginEditorView(record: record, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
        .alert("Document", isPresented: errorBinding, presenting: errorMessage) { _ in
            Button("Fermer", role: .cancel) { errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Le document affiché en salle

    private var documentSection: some View {
        Section {
            Button {
                prepareSheet()
            } label: {
                if isPreparing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Préparation…")
                    }
                } else {
                    Label("Préparer le document d'affichage", systemImage: "doc.text")
                }
            }
            .disabled(isPreparing)

            if let sheetURL {
                ShareLink(item: sheetURL) {
                    Label("Imprimer ou partager", systemImage: "printer")
                }
            }
        } header: {
            Text("Affichage en salle")
        } footer: {
            Text("Le document reprend les \(onMenu.count) viande(s) à la carte, avec leurs trois pays, votre entreprise et la mention réglementaire. Les photos d'étiquettes n'y figurent pas : il est vu par vos clients.")
        }
    }

    private func prepareSheet() {
        isPreparing = true

        Task { @MainActor in
            await Task.yield()

            let sheet = MeatOriginSheet(
                entries: records,
                establishment: establishments.first,
                responsibleName: establishments.first?.managerName.isEmpty == false
                    ? (establishments.first?.managerName ?? "")
                    : preferences.operatorName
            )

            do {
                sheetURL = try MeatOriginSheetService.render(sheet)
            } catch {
                errorMessage = "Le document n'a pas pu être créé. \(error.localizedDescription)"
            }

            isPreparing = false
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func row(_ record: BeefOriginRecord) -> some View {
        Button {
            editedRecord = record
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(
                    systemImage: record.species.systemImage,
                    tint: record.isOnMenu ? (record.isComplete ? .brand : .orange) : .secondary
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(record.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(record.isOnMenu ? Color.primary : Color.secondary)
                        StatusBadge(text: record.species.label, color: .brand)
                        Spacer(minLength: 0)
                    }

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

            Button {
                toggleMenu(record)
            } label: {
                Label(
                    record.isOnMenu ? "Retirer" : "Remettre",
                    systemImage: record.isOnMenu ? "eye.slash" : "eye"
                )
            }
            .tint(.orange)
        }
    }

    private func toggleMenu(_ record: BeefOriginRecord) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        record.isOnMenu.toggle()
        sheetURL = nil
        try? modelContext.save()
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
        sheetURL = nil
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
    @State private var species: MeatSpecies
    @State private var isOnMenu: Bool
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
        _species = State(initialValue: record?.species ?? .bovine)
        _isOnMenu = State(initialValue: record?.isOnMenu ?? true)
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
                Section {
                    Picker("Espèce", selection: $species) {
                        ForEach(MeatSpecies.allCases) { candidate in
                            Label(candidate.label, systemImage: candidate.systemImage)
                                .tag(candidate)
                        }
                    }

                    TextField("Désignation (entrecôte, haché…)", text: $cutName)
                    TextField("Numéro de lot", text: $batchNumber)
                    TextField("Fournisseur", text: $supplier)
                    TextField("Quantité (facultatif)", text: $quantity)
                    DatePicker("Réceptionné le", selection: $receivedAt, in: ...Date.now)
                } header: {
                    Text("Viande")
                } footer: {
                    Text("Une fiche par viande proposée. Le décret de 2022 vise les quatre espèces, pas seulement le bœuf.")
                }

                Section {
                    Toggle("Proposée à la carte", isOn: $isOnMenu)
                } footer: {
                    Text("Seules les viandes cochées apparaissent sur le document affiché en salle. Décochez celle que vous ne servez plus : sa fiche reste dans le registre.")
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
            .navigationTitle(record == nil ? "Nouvelle viande" : "Modifier")
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
        target.species = species
        target.isOnMenu = isOnMenu
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
