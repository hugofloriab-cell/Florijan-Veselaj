//
//  HistoryView.swift
//  HACCPPocket
//
//  Historique global : tous les registres réunis dans une seule frise
//  chronologique, avec recherche et filtres.
//
//  En cas de contrôle, la question n'est jamais « montrez-moi vos relevés de
//  température » mais « qu'avez-vous fait le 12 mars ? » ou « ce lot, vous
//  l'avez reçu quand ? ». Il fallait donc un écran qui traverse les registres
//  au lieu de les cloisonner.
//

import SwiftUI
import SwiftData

// MARK: - Type d'enregistrement

enum HistoryKind: String, CaseIterable, Identifiable {
    case temperature
    case product
    case delivery
    case cleaning
    case thermal
    case oil
    case pest
    case training

    var id: String { rawValue }

    var label: String {
        switch self {
        case .temperature: "Températures"
        case .product:     "Produits"
        case .delivery:    "Réceptions"
        case .cleaning:    "Nettoyage"
        case .thermal:     "Process thermiques"
        case .oil:         "Huiles"
        case .pest:        "Nuisibles"
        case .training:    "Formations"
        }
    }

    var systemImage: String {
        switch self {
        case .temperature: "thermometer.medium"
        case .product:     "shippingbox.and.arrow.backward"
        case .delivery:    "shippingbox"
        case .cleaning:    "sparkles"
        case .thermal:     "thermometer.variable"
        case .oil:         "drop.triangle"
        case .pest:        "ant"
        case .training:    "graduationcap"
        }
    }

    var tint: Color {
        switch self {
        case .temperature: .blue
        case .product:     .orange
        case .delivery:    .teal
        case .cleaning:    .green
        case .thermal:     .purple
        case .oil:         .brown
        case .pest:        .pink
        case .training:    .indigo
        }
    }
}

// MARK: - Entrée d'historique

/// Une ligne de la frise, indépendante du modèle SwiftData d'origine : la vue
/// n'a besoin que de quoi afficher, chercher et détailler.
struct HistoryEntry: Identifiable {

    struct Detail: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    let id: String
    let date: Date
    let kind: HistoryKind
    let title: String
    let subtitle: String
    let operatorName: String
    /// `nil` quand la notion de conformité n'a pas de sens (une formation).
    let isCompliant: Bool?
    let details: [Detail]

    /// Texte sur lequel porte la recherche, accents et casse neutralisés.
    var searchIndex: String {
        ([title, subtitle, operatorName, kind.label] + details.map { "\($0.label) \($0.value)" })
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: AppFormatters.locale)
    }
}

/// Une journée de la frise. Un type nommé plutôt qu'un tuple : `ForEach` a
/// besoin d'une identité, et Swift n'autorise pas les key paths sur un tuple.
private struct HistoryDayGroup: Identifiable {
    let day: Date
    var entries: [HistoryEntry]
    var id: Date { day }
}

// MARK: - Période

enum HistoryPeriod: String, CaseIterable, Identifiable {
    case week
    case month
    case year
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week:  "7 jours"
        case .month: "30 jours"
        case .year:  "12 mois"
        case .all:   "Tout"
        }
    }

    /// Date la plus ancienne retenue, `nil` pour l'historique complet.
    func startDate(from reference: Date = .now, calendar: Calendar = .current) -> Date? {
        switch self {
        case .week:  calendar.date(byAdding: .day, value: -7, to: reference)
        case .month: calendar.date(byAdding: .day, value: -30, to: reference)
        case .year:  calendar.date(byAdding: .month, value: -12, to: reference)
        case .all:   nil
        }
    }
}

// MARK: - Écran

struct HistoryView: View {

    @Query(sort: \TemperatureReading.recordedAt, order: .reverse)
    private var readings: [TemperatureReading]

    @Query(sort: \TrackedProduct.openedAt, order: .reverse)
    private var products: [TrackedProduct]

    @Query(sort: \DeliveryCheck.receivedAt, order: .reverse)
    private var deliveries: [DeliveryCheck]

    @Query(sort: \CleaningRecord.completedAt, order: .reverse)
    private var cleaningRecords: [CleaningRecord]

    @Query(sort: \ThermalProcessRecord.startedAt, order: .reverse)
    private var thermalRecords: [ThermalProcessRecord]

    @Query(sort: \OilCheckRecord.checkedAt, order: .reverse)
    private var oilChecks: [OilCheckRecord]

    @Query(sort: \PestControlVisit.visitedAt, order: .reverse)
    private var pestVisits: [PestControlVisit]

    @Query(sort: \StaffTraining.completedAt, order: .reverse)
    private var trainings: [StaffTraining]

    @State private var searchText = ""
    @State private var period: HistoryPeriod = .month
    @State private var selectedKinds: Set<HistoryKind> = []
    @State private var onlyNonCompliant = false
    @State private var visibleLimit = 150
    @State private var selectedEntry: HistoryEntry?

    // MARK: Corps

    var body: some View {
        List {
            filterSection

            if filteredEntries.isEmpty {
                emptyState
            } else {
                ForEach(groupedEntries) { group in
                    Section(AppFormatters.sentenceCased(AppFormatters.longDay(group.day))) {
                        ForEach(group.entries) { entry in
                            Button {
                                selectedEntry = entry
                            } label: {
                                HistoryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if filteredEntries.count > visibleLimit {
                    Section {
                        Button("Afficher 150 enregistrements de plus") {
                            visibleLimit += 150
                        }
                    } footer: {
                        Text("\(filteredEntries.count) enregistrements correspondent à votre recherche.")
                    }
                }
            }
        }
        .navigationTitle("Historique")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Produit, lot, fournisseur, opérateur…"
        )
        .onChange(of: searchText) { _, _ in visibleLimit = 150 }
        .onChange(of: period) { _, _ in visibleLimit = 150 }
        .sheet(item: $selectedEntry) { entry in
            HistoryDetailSheet(entry: entry)
        }
    }

    // MARK: Filtres

    private var filterSection: some View {
        Section {
            Picker("Période", selection: $period) {
                ForEach(HistoryPeriod.allCases) { period in
                    Text(period.label).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HistoryKind.allCases) { kind in
                        FilterChip(
                            label: kind.label,
                            systemImage: kind.systemImage,
                            tint: kind.tint,
                            isOn: selectedKinds.contains(kind)
                        ) {
                            toggle(kind)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            Toggle("Anomalies uniquement", isOn: $onlyNonCompliant)
        } footer: {
            Text(selectedKinds.isEmpty
                 ? "Tous les registres sont affichés."
                 : "\(selectedKinds.count) registre(s) sélectionné(s).")
        }
    }

    private func toggle(_ kind: HistoryKind) {
        if selectedKinds.contains(kind) {
            selectedKinds.remove(kind)
        } else {
            selectedKinds.insert(kind)
        }
        visibleLimit = 150
    }

    private var emptyState: some View {
        Section {
            ContentUnavailableView(
                searchText.isEmpty ? "Aucun enregistrement" : "Aucun résultat",
                systemImage: searchText.isEmpty ? "clock" : "magnifyingglass",
                description: Text(searchText.isEmpty
                                  ? "Les opérations que vous enregistrez apparaîtront ici."
                                  : "Essayez un autre mot, ou élargissez la période.")
            )
            .listRowBackground(Color.clear)
        }
    }

    // MARK: Construction de la frise

    private var allEntries: [HistoryEntry] {
        var entries: [HistoryEntry] = []
        // Réservation calculée pas à pas : une longue chaîne d'additions dans
        // un argument générique coûte cher au vérificateur de types.
        var expected: Int = 0
        expected += readings.count
        expected += products.count
        expected += deliveries.count
        expected += cleaningRecords.count
        expected += thermalRecords.count
        expected += oilChecks.count
        expected += pestVisits.count
        expected += trainings.count
        entries.reserveCapacity(expected)

        entries.append(contentsOf: readings.map { entry(for: $0) })
        entries.append(contentsOf: products.map { entry(for: $0) })
        entries.append(contentsOf: deliveries.map { entry(for: $0) })
        entries.append(contentsOf: cleaningRecords.map { entry(for: $0) })
        entries.append(contentsOf: thermalRecords.map { entry(for: $0) })
        entries.append(contentsOf: oilChecks.map { entry(for: $0) })
        entries.append(contentsOf: pestVisits.map { entry(for: $0) })
        entries.append(contentsOf: trainings.map { entry(for: $0) })

        return entries.sorted { $0.date > $1.date }
    }

    private var filteredEntries: [HistoryEntry] {
        let start = period.startDate()
        let needle = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: AppFormatters.locale)

        return allEntries.filter { entry in
            if let start, entry.date < start { return false }
            if !selectedKinds.isEmpty && !selectedKinds.contains(entry.kind) { return false }
            if onlyNonCompliant && entry.isCompliant != false { return false }
            if !needle.isEmpty && !entry.searchIndex.contains(needle) { return false }
            return true
        }
    }

    /// Regroupement par jour, dans l'ordre déjà trié.
    private var groupedEntries: [HistoryDayGroup] {
        let calendar = Calendar.current
        var groups: [HistoryDayGroup] = []

        for entry in filteredEntries.prefix(visibleLimit) {
            let day = calendar.startOfDay(for: entry.date)
            if let index = groups.lastIndex(where: { $0.day == day }) {
                groups[index].entries.append(entry)
            } else {
                groups.append(HistoryDayGroup(day: day, entries: [entry]))
            }
        }

        return groups
    }

    // MARK: Conversions

    private func entry(for reading: TemperatureReading) -> HistoryEntry {
        HistoryEntry(
            id: "temp-\(reading.persistentModelID.hashValue)",
            date: reading.recordedAt,
            kind: .temperature,
            title: reading.equipment?.name ?? "Enceinte supprimée",
            subtitle: "\(reading.formattedValue) · \(reading.moment.label)",
            operatorName: reading.operatorName,
            isCompliant: reading.isCompliant,
            details: [
                .init(label: "Heure", value: AppFormatters.time(reading.recordedAt)),
                .init(label: "Température", value: reading.formattedValue),
                .init(label: "Plage acceptée", value: AppFormatters.range(reading.appliedRange)),
                .init(label: "Moment", value: reading.moment.label),
                .init(label: "Commentaire", value: reading.comment),
                .init(label: "Action corrective", value: reading.correctiveAction)
            ].filter { !$0.value.isEmpty }
        )
    }

    private func entry(for product: TrackedProduct) -> HistoryEntry {
        HistoryEntry(
            id: "product-\(product.identifier.uuidString)",
            date: product.openedAt,
            kind: .product,
            title: product.name,
            subtitle: "Entamé · limite le \(AppFormatters.shortDate(product.effectiveLimitDate))",
            operatorName: "",
            isCompliant: product.status == .discarded ? false : nil,
            details: [
                .init(label: "Ouverture", value: AppFormatters.dateAndTime(product.openedAt)),
                .init(label: "DLC secondaire", value: AppFormatters.shortDate(product.secondaryLimitDate)),
                .init(label: "DLC fournisseur", value: product.supplierExpiryDate.map { AppFormatters.shortDate($0) } ?? ""),
                .init(label: "Lot", value: product.batchNumber),
                .init(label: "Fournisseur", value: product.supplier),
                .init(label: "Code-barres", value: product.barcode),
                .init(label: "Zone", value: product.storage.label),
                .init(label: "Statut", value: product.status.label),
                .init(label: "Motif", value: product.discardReason),
                .init(label: "Notes", value: product.notes)
            ].filter { !$0.value.isEmpty }
        )
    }

    private func entry(for delivery: DeliveryCheck) -> HistoryEntry {
        HistoryEntry(
            id: "delivery-\(delivery.persistentModelID.hashValue)",
            date: delivery.receivedAt,
            kind: .delivery,
            title: delivery.supplierName,
            subtitle: [delivery.productLabel, delivery.decision.label]
                .filter { !$0.isEmpty }
                .joined(separator: " · "),
            operatorName: delivery.operatorName,
            isCompliant: delivery.isFullyCompliant,
            details: [
                .init(label: "Heure", value: AppFormatters.time(delivery.receivedAt)),
                .init(label: "Produit", value: delivery.productLabel),
                .init(label: "Lot", value: delivery.batchNumber),
                .init(label: "Température", value: delivery.formattedTemperature),
                .init(label: "Décision", value: delivery.decision.label),
                .init(label: "Motif", value: delivery.reason),
                .init(label: "Anomalies", value: delivery.anomalies.joined(separator: ", ")),
                .init(label: "Observations", value: delivery.notes)
            ].filter { !$0.value.isEmpty }
        )
    }

    private func entry(for record: CleaningRecord) -> HistoryEntry {
        HistoryEntry(
            id: "cleaning-\(record.persistentModelID.hashValue)",
            date: record.completedAt,
            kind: .cleaning,
            title: record.taskTitle,
            subtitle: record.productUsed.isEmpty ? "Nettoyage réalisé" : record.productUsed,
            operatorName: record.operatorName,
            isCompliant: nil,
            details: [
                .init(label: "Heure", value: AppFormatters.time(record.completedAt)),
                .init(label: "Produit utilisé", value: record.productUsed),
                .init(label: "Zone", value: record.task?.zone ?? ""),
                .init(label: "Fréquence", value: record.task?.frequency.label ?? ""),
                .init(label: "Commentaire", value: record.comment),
                .init(label: "Photo", value: record.photoData == nil ? "" : "Oui")
            ].filter { !$0.value.isEmpty }
        )
    }

    private func entry(for record: ThermalProcessRecord) -> HistoryEntry {
        HistoryEntry(
            id: "thermal-\(record.persistentModelID.hashValue)",
            date: record.startedAt,
            kind: .thermal,
            title: record.productName,
            subtitle: record.isFinished
                ? "\(record.kind.shortLabel) · \(record.formattedDuration())"
                : "\(record.kind.shortLabel) · en cours",
            operatorName: record.operatorName,
            isCompliant: record.isFinished ? record.isCompliant : nil,
            details: [
                .init(label: "Type", value: record.kind.label),
                .init(label: "Exigence", value: record.kind.requirement),
                .init(label: "Début", value: AppFormatters.dateAndTime(record.startedAt)),
                .init(label: "Température de départ", value: AppFormatters.temperature(record.startTemperature)),
                .init(label: "Fin", value: record.finishedAt.map { AppFormatters.dateAndTime($0) } ?? "En cours"),
                .init(label: "Température finale", value: record.endTemperature.map { AppFormatters.temperature($0) } ?? ""),
                .init(label: "Durée", value: record.isFinished ? record.formattedDuration() : ""),
                .init(label: "Lot", value: record.batchNumber),
                .init(label: "Non-conformité", value: record.failureReason ?? ""),
                .init(label: "Action corrective", value: record.correctiveAction),
                .init(label: "Commentaire", value: record.comment)
            ].filter { !$0.value.isEmpty }
        )
    }

    private func entry(for check: OilCheckRecord) -> HistoryEntry {
        HistoryEntry(
            id: "oil-\(check.persistentModelID.hashValue)",
            date: check.checkedAt,
            kind: .oil,
            title: check.fryerName,
            subtitle: "\(check.formattedPolarCompounds) · \(check.action.label)",
            operatorName: check.operatorName,
            isCompliant: check.isCompliant,
            details: [
                .init(label: "Heure", value: AppFormatters.time(check.checkedAt)),
                .init(label: "Composés polaires", value: check.formattedPolarCompounds),
                .init(label: "Limite réglementaire", value: "\(Int(check.polarCompoundsLimit)) %"),
                .init(label: "Aspect", value: check.appearance.label),
                .init(label: "Action", value: check.action.label),
                .init(label: "Commentaire", value: check.comment)
            ].filter { !$0.value.isEmpty }
        )
    }

    private func entry(for visit: PestControlVisit) -> HistoryEntry {
        HistoryEntry(
            id: "pest-\(visit.persistentModelID.hashValue)",
            date: visit.visitedAt,
            kind: .pest,
            title: visit.company,
            subtitle: visit.statusLabel,
            operatorName: visit.technician,
            isCompliant: !visit.hasInfestation,
            details: [
                .init(label: "Technicien", value: visit.technician),
                .init(label: "Constats", value: visit.findings),
                .init(label: "Appâts remplacés", value: visit.baitsReplaced ? "Oui" : "Non"),
                .init(label: "Dispositifs", value: visit.deviceCount > 0 ? "\(visit.deviceCount)" : ""),
                .init(label: "Actions menées", value: visit.actionsTaken),
                .init(label: "Prochaine visite", value: visit.nextVisitDate.map { AppFormatters.shortDate($0) } ?? ""),
                .init(label: "Rapport", value: visit.reportPhotoData == nil ? "" : "Photo jointe")
            ].filter { !$0.value.isEmpty }
        )
    }

    private func entry(for training: StaffTraining) -> HistoryEntry {
        HistoryEntry(
            id: "training-\(training.persistentModelID.hashValue)",
            date: training.completedAt,
            kind: .training,
            title: training.personName,
            subtitle: training.title,
            operatorName: training.personName,
            isCompliant: training.isExpired() ? false : nil,
            details: [
                .init(label: "Formation", value: training.title),
                .init(label: "Organisme", value: training.organisation),
                .init(label: "Obtenue le", value: AppFormatters.shortDate(training.completedAt)),
                .init(label: "Valable jusqu'au", value: training.expiresAt.map { AppFormatters.shortDate($0) } ?? "Sans expiration"),
                .init(label: "Statut", value: training.statusLabel),
                .init(label: "Attestation", value: training.hasCertificate ? "Jointe" : ""),
                .init(label: "Notes", value: training.notes)
            ].filter { !$0.value.isEmpty }
        )
    }
}

// MARK: - Ligne

private struct HistoryRow: View {

    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            RowIcon(systemImage: entry.kind.systemImage, tint: entry.kind.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text(entry.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !entry.operatorName.isEmpty {
                    Text(entry.operatorName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(AppFormatters.time(entry.date))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                if entry.isCompliant == false {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Puce de filtre

private struct FilterChip: View {

    let label: String
    let systemImage: String
    let tint: Color
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isOn ? tint.opacity(0.18) : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(isOn ? tint : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Détail

private struct HistoryDetailSheet: View {

    @Environment(\.dismiss) private var dismiss

    let entry: HistoryEntry

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        RowIcon(systemImage: entry.kind.systemImage, tint: entry.kind.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.headline)
                            Text(AppFormatters.dateAndTime(entry.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let isCompliant = entry.isCompliant {
                            StatusBadge(
                                text: isCompliant ? "Conforme" : "Anomalie",
                                color: isCompliant ? .green : .red
                            )
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(entry.kind.label)
                }

                if !entry.operatorName.isEmpty {
                    Section("Opérateur") {
                        Text(entry.operatorName)
                    }
                }

                if !entry.details.isEmpty {
                    Section("Détail de l'enregistrement") {
                        ForEach(entry.details) { detail in
                            LabeledContent(detail.label) {
                                Text(detail.value)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Enregistrement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
    .modelContainer(AppSchema.preview)
}
