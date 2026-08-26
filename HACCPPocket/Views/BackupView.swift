//
//  BackupView.swift
//  HACCPPocket
//
//  Écran de sauvegarde et de restauration.
//
//  Toutes les données vivent dans l'appareil. Cet écran est donc le seul
//  endroit d'où l'utilisateur peut les faire sortir — pour les archiver, les
//  transmettre, ou repartir sur un nouveau téléphone.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Message affiché après une opération. Porte son propre titre pour que
/// l'alerte reste compréhensible sans contexte.
struct BackupMessage: Identifiable {
    let id = UUID()
    let title: String
    let text: String
    let isError: Bool

    static func success(_ text: String) -> BackupMessage {
        BackupMessage(title: "C'est fait", text: text, isError: false)
    }

    static func failure(_ text: String) -> BackupMessage {
        BackupMessage(title: "Sauvegarde", text: text, isError: true)
    }
}

struct BackupView: View {

    @Environment(\.modelContext) private var modelContext

    // Compteurs affichés avant l'export : l'utilisateur doit voir ce qu'il
    // s'apprête à sauvegarder.
    @Query private var equipments: [Equipment]
    @Query private var readings: [TemperatureReading]
    @Query private var products: [TrackedProduct]
    @Query private var deliveries: [DeliveryCheck]
    @Query private var cleaningRecords: [CleaningRecord]
    @Query private var thermalRecords: [ThermalProcessRecord]
    @Query private var oilChecks: [OilCheckRecord]
    @Query private var pestVisits: [PestControlVisit]
    @Query private var trainings: [StaffTraining]
    @Query private var dishes: [Dish]
    @Query private var thawings: [ThawingRecord]
    @Query private var foodSamples: [FoodSample]
    @Query private var sanitizingFreezes: [SanitizingFreezeRecord]
    @Query private var beefOrigins: [BeefOriginRecord]
    @Query private var hygieneChecks: [ShiftHygieneCheck]
    @Query private var medicalRecords: [MedicalFitnessRecord]
    @Query private var cleaningProducts: [CleaningProduct]
    @Query private var documents: [RegulatoryDocument]
    @Query private var maintenance: [EquipmentMaintenance]
    @Query private var recalls: [ProductRecall]
    @Query private var analyses: [LabAnalysis]
    @Query private var waterControls: [WaterControl]
    @Query private var oilCollections: [WasteOilCollection]
    @Query private var seals: [IntegritySeal]

    @AppStorage("haccp.backup.lastExportedAt") private var lastExportTimestamp: Double = 0
    @AppStorage("haccp.backup.includePhotos") private var includePhotos = true

    @State private var backupURL: URL?
    @State private var isPreparing = false

    @State private var showsImporter = false
    @State private var pendingArchive: BackupArchive?
    @State private var pendingURL: URL?
    @State private var showsRestoreConfirmation = false
    @State private var showsEraseConfirmation = false

    @State private var archivedStores: [AppSchema.ArchivedStore] = []
    @State private var storeToRestore: AppSchema.ArchivedStore?
    @State private var showsRestartNotice = false

    /// Un seul état pour les messages : empiler plusieurs alertes sur la même
    /// vue est une source d'ennuis, et l'utilisateur n'en voit qu'une à la fois.
    @State private var message: BackupMessage?

    // MARK: - Corps

    var body: some View {
        List {
            summarySection
            archivedStoresSection
            exportSection
            importSection
            eraseSection
        }
        .onAppear { archivedStores = AppSchema.archivedStores() }
        .navigationTitle("Sauvegarde")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: includePhotos) { _, _ in
            // Le fichier déjà préparé ne correspond plus au réglage choisi.
            backupURL = nil
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert(
            "Restaurer cette sauvegarde ?",
            isPresented: $showsRestoreConfirmation,
            presenting: pendingArchive
        ) { archive in
            Button("Remplacer mes données", role: .destructive) {
                restore(archive)
            }
            Button("Annuler", role: .cancel) {
                pendingArchive = nil
            }
        } message: { archive in
            Text(restoreMessage(for: archive))
        }
        .alert(
            "Remettre cette base en service ?",
            isPresented: restoreConfirmationBinding,
            presenting: storeToRestore
        ) { archive in
            Button("Remettre en service") { requestRestore(archive) }
            Button("Annuler", role: .cancel) { storeToRestore = nil }
        } message: { archive in
            Text("La base actuelle (\(totalRecords) enregistrements) sera écartée à son tour, sans être supprimée. L'opération est donc réversible : si vous vous trompez de fichier, vous pourrez revenir en arrière.")
        }
        .alert("Fermez puis rouvrez l'application", isPresented: $showsRestartNotice) {
            Button("J'ai compris", role: .cancel) { }
        } message: {
            Text("L'échange se fera au prochain démarrage, quand plus rien ne tient les fichiers ouverts.\n\nFermez complètement HACCP Pocket — glissez vers le haut depuis le bas de l'écran, puis balayez la fenêtre de l'application — et rouvrez-la.")
        }
        .alert("Effacer toutes les données ?", isPresented: $showsEraseConfirmation) {
            Button("Tout effacer", role: .destructive) { eraseEverything() }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("Les \(totalRecords) enregistrements de l'application seront supprimés définitivement. Exportez une sauvegarde avant de continuer.")
        }
        .alert(
            message?.title ?? "",
            isPresented: messageBinding,
            presenting: message
        ) { shown in
            Button(shown.isError ? "Fermer" : "Parfait", role: .cancel) { message = nil }
        } message: { shown in
            Text(shown.text)
        }
    }

    // MARK: - Résumé

    private var totalRecords: Int {
        // Même précaution que dans `BackupArchive` : une longue chaîne
        // d'additions coûte cher à vérifier, on accumule plutôt.
        var total: Int = 0
        total += equipments.count
        total += readings.count
        total += products.count
        total += deliveries.count
        total += cleaningRecords.count
        total += thermalRecords.count
        total += oilChecks.count
        total += pestVisits.count
        total += trainings.count
        total += dishes.count
        total += thawings.count
        total += foodSamples.count
        total += sanitizingFreezes.count
        total += beefOrigins.count
        total += hygieneChecks.count
        total += medicalRecords.count
        total += cleaningProducts.count
        total += documents.count
        total += maintenance.count
        total += recalls.count
        total += analyses.count
        total += waterControls.count
        total += oilCollections.count
        total += seals.count
        return total
    }

    private var lastExportDate: Date? {
        lastExportTimestamp > 0 ? Date(timeIntervalSince1970: lastExportTimestamp) : nil
    }

    private var summarySection: some View {
        Section {
            LabeledContent("Enregistrements", value: "\(totalRecords)")
            LabeledContent("Relevés de température", value: "\(readings.count)")
            LabeledContent("Produits entamés", value: "\(products.count)")
            LabeledContent("Opérations de nettoyage", value: "\(cleaningRecords.count)")

            if let lastExportDate {
                LabeledContent("Dernière sauvegarde") {
                    Text(AppFormatters.dateAndTime(lastExportDate))
                        .foregroundStyle(isExportStale ? Color.orange : Color.secondary)
                }
            } else {
                Label("Aucune sauvegarde effectuée", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Contenu de l'application")
        } footer: {
            Text("Vos données sont enregistrées uniquement dans cet appareil. Si vous le perdez ou le réinitialisez, elles disparaissent avec lui.")
        }
    }

    /// Au-delà d'un mois, la sauvegarde ne protège plus grand-chose.
    private var isExportStale: Bool {
        guard let lastExportDate else { return true }
        return Date.now.timeIntervalSince(lastExportDate) > 30 * 24 * 3600
    }

    // MARK: - Bases mises de côté

    @ViewBuilder
    private var archivedStoresSection: some View {
        if !archivedStores.isEmpty {
            Section {
                ForEach(archivedStores) { archive in
                    Button {
                        storeToRestore = archive
                    } label: {
                        HStack(spacing: 12) {
                            RowIcon(systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90", tint: .orange)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Base du \(AppFormatters.dateAndTime(archive.modifiedAt))")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(sizeLabel(archive.byteSize))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            Text("Remettre")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.brand)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Bases mises de côté")
            } footer: {
                Text("Une base que l'application n'a pas su ouvrir est écartée plutôt que supprimée. Vous pouvez la remettre en service : c'est sans risque, la base actuelle est conservée de la même façon.")
            }
        }
    }

    private func requestRestore(_ archive: AppSchema.ArchivedStore) {
        AppSchema.requestRestore(of: archive)
        storeToRestore = nil
        showsRestartNotice = true
    }

    private func sizeLabel(_ bytes: Int) -> String {
        let megabytes = Double(bytes) / 1_048_576
        if megabytes >= 1 {
            return String(format: "%.1f Mo", megabytes)
        }
        return String(format: "%.0f Ko", Double(bytes) / 1024)
    }

    private var restoreConfirmationBinding: Binding<Bool> {
        Binding(get: { storeToRestore != nil }, set: { if !$0 { storeToRestore = nil } })
    }

    // MARK: - Export

    private var exportSection: some View {
        Section {
            Toggle("Inclure les photos", isOn: $includePhotos)

            Button {
                prepareBackup()
            } label: {
                if isPreparing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Préparation…")
                    }
                } else {
                    Label("Préparer la sauvegarde", systemImage: "arrow.down.doc")
                }
            }
            .disabled(isPreparing || totalRecords == 0)

            if let backupURL {
                ShareLink(item: backupURL) {
                    Label("Enregistrer ou envoyer le fichier", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("Exporter")
        } footer: {
            Text(includePhotos
                 ? "Le fichier contient tout, photos comprises. Enregistrez-le dans iCloud Drive, sur une clé, ou envoyez-le-vous par e-mail."
                 : "Sans les photos, le fichier reste très léger et passe sans problème par e-mail. Les photos ne seront pas restaurables depuis cette sauvegarde.")
        }
    }

    private func prepareBackup() {
        isPreparing = true

        // Un passage par une tâche laisse SwiftUI afficher l'indicateur avant
        // l'encodage, qui peut prendre une seconde ou deux avec les photos.
        Task { @MainActor in
            await Task.yield()

            do {
                let archive = try BackupService.makeArchive(
                    context: modelContext,
                    includePhotos: includePhotos,
                    appVersion: appVersion
                )
                backupURL = try BackupService.writeToTemporaryFile(archive)
                lastExportTimestamp = archive.exportedAt.timeIntervalSince1970
            } catch {
                message = .failure("La sauvegarde n'a pas pu être créée. \(error.localizedDescription)")
            }

            isPreparing = false
        }
    }

    // MARK: - Import

    private var importSection: some View {
        Section {
            Button {
                showsImporter = true
            } label: {
                Label("Restaurer depuis un fichier", systemImage: "arrow.up.doc")
            }
        } header: {
            Text("Restaurer")
        } footer: {
            Text("La restauration remplace la totalité des données de l'application par celles du fichier. Rien n'est fusionné : un registre en double vaudrait moins qu'un registre juste.")
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let archive = try BackupService.readArchive(at: url)
                pendingURL = url
                pendingArchive = archive
                showsRestoreConfirmation = true
            } catch {
                message = .failure(error.localizedDescription)
            }

        case .failure(let error):
            message = .failure(error.localizedDescription)
        }
    }

    private func restoreMessage(for archive: BackupArchive) -> String {
        var lines = [
            "Sauvegarde du \(AppFormatters.dateAndTime(archive.exportedAt))",
            "\(archive.totalRecords) enregistrements"
        ]
        if !archive.includesPhotos {
            lines.append("Cette sauvegarde ne contient pas les photos.")
        }
        lines.append("Vos \(totalRecords) enregistrements actuels seront définitivement remplacés.")
        return lines.joined(separator: "\n")
    }

    private func restore(_ archive: BackupArchive) {
        do {
            let count = try BackupService.restore(archive, into: modelContext)
            message = .success("\(count) enregistrements restaurés.")
        } catch {
            message = .failure("La restauration a échoué. \(error.localizedDescription)")
        }
        pendingArchive = nil
        pendingURL = nil
    }

    // MARK: - Effacement

    private var eraseSection: some View {
        Section {
            Button(role: .destructive) {
                showsEraseConfirmation = true
            } label: {
                Label("Effacer toutes les données", systemImage: "trash")
            }
            .disabled(totalRecords == 0)
        } footer: {
            Text("À n'utiliser que pour repartir de zéro, par exemple en changeant d'établissement.")
        }
    }

    private func eraseEverything() {
        do {
            try BackupService.eraseEverything(in: modelContext)
            message = .success("Toutes les données ont été effacées.")
        } catch {
            message = .failure("L'effacement a échoué. \(error.localizedDescription)")
        }
    }

    // MARK: - Divers

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private var messageBinding: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }
}

#Preview {
    NavigationStack {
        BackupView()
    }
    .modelContainer(AppSchema.preview)
}
