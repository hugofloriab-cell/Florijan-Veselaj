//
//  SanitizingFreezeView.swift
//  HACCPPocket
//
//  Traitement assainissant du poisson destiné à la consommation crue.
//

import SwiftUI
import SwiftData

struct SanitizingFreezeListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \SanitizingFreezeRecord.startedAt, order: .reverse)
    private var records: [SanitizingFreezeRecord]

    @State private var isCreating = false
    @State private var finishedRecord: SanitizingFreezeRecord?
    @State private var showsPaywall = false

    private var running: [SanitizingFreezeRecord] { records.filter { !$0.isFinished } }
    private var completed: [SanitizingFreezeRecord] { records.filter(\.isFinished) }

    var body: some View {
        List {
            Section { ProtocolLink(procedure: .sanitizingFreeze) }

            if records.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Aucun traitement enregistré", systemImage: "fish")
                    } description: {
                        Text("Tout poisson servi cru — tartare, carpaccio, sushi, marinade, fumage à froid — doit passer par une congélation assainissante. C'est le premier document demandé dès qu'un établissement affiche du poisson cru.")
                    } actions: {
                        Button("Démarrer un traitement") { create() }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if !running.isEmpty {
                Section("En cours") {
                    // Le chronomètre se rafraîchit tout seul : un barème de
                    // 24 heures se surveille sur plusieurs services.
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        ForEach(running) { record in
                            runningRow(record, now: context.date)
                        }
                    }
                }
            }

            if !completed.isEmpty {
                Section("Terminés") {
                    ForEach(completed) { record in
                        completedRow(record)
                    }
                }
            }
        }
        .navigationTitle("Poisson cru")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { create() } label: {
                    Label("Démarrer un traitement", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            SanitizingFreezeStartView(context: modelContext)
        }
        .sheet(item: $finishedRecord) { record in
            SanitizingFreezeFinishView(record: record, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }

    // MARK: - Lignes

    private func runningRow(_ record: SanitizingFreezeRecord, now: Date) -> some View {
        let met = record.isScheduleMet(at: now)

        return Button {
            finish(record)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    RowIcon(systemImage: "snowflake", tint: met ? .green : .orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("\(record.schedule.label) · lot \(record.batchNumber.isEmpty ? "non précisé" : record.batchNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Text(record.formattedDuration(at: now))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(met ? Color.green : Color.orange)
                }

                ProgressView(value: record.timeProgress(at: now))
                    .tint(met ? .green : .orange)

                Text(met
                     ? "Barème atteint — vous pouvez clôturer après relevé de la température à cœur."
                     : "Encore \(formattedRemaining(record, now: now)) avant d'atteindre le barème.")
                    .font(.caption)
                    .foregroundStyle(met ? Color.green : Color.secondary)
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

    private func formattedRemaining(_ record: SanitizingFreezeRecord, now: Date) -> String {
        let remaining = Int(max(0, record.remainingTime(at: now)))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        return hours > 0 ? "\(hours) h \(String(format: "%02d", minutes))" : "\(minutes) min"
    }

    private func completedRow(_ record: SanitizingFreezeRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RowIcon(
                systemImage: record.isCompliant ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                tint: record.isCompliant ? .green : .red
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(record.displayName)
                    .font(.subheadline.weight(.medium))

                Text("\(AppFormatters.shortDate(record.startedAt)) · \(record.formattedDuration()) · \(record.schedule.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let reason = record.failureReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            StatusBadge(
                text: record.statusLabel,
                color: record.isCompliant ? .green : .red
            )
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(record) } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func create() {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        isCreating = true
    }

    private func finish(_ record: SanitizingFreezeRecord) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        finishedRecord = record
    }

    private func delete(_ record: SanitizingFreezeRecord) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        modelContext.delete(record)
        try? modelContext.save()
    }
}

// MARK: - Démarrage

struct SanitizingFreezeStartView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferences.self) private var preferences

    let context: ModelContext

    @State private var productName = ""
    @State private var batchNumber = ""
    @State private var supplier = ""
    @State private var intendedUse = ""
    @State private var schedule: SanitizingSchedule = .minus20
    @State private var equipmentName = ""
    @State private var quantity = ""
    @State private var startedAt = Date.now
    @State private var operatorName = ""
    @State private var comment = ""

    var body: some View {
        NavigationStack {
            Form {
                Section { ProtocolLink(procedure: .sanitizingFreeze) }

                Section("Produit") {
                    TextField("Espèce et désignation", text: $productName)
                    TextField("Numéro de lot", text: $batchNumber)
                    TextField("Fournisseur", text: $supplier)
                    TextField("Quantité (facultatif)", text: $quantity)
                }

                Section {
                    TextField("Tartare, sushi, carpaccio, fumage…", text: $intendedUse)
                } header: {
                    Text("Destination")
                } footer: {
                    Text("Le traitement est obligatoire dès que le poisson est destiné à être servi cru, mariné, ou fumé à froid.")
                }

                Section {
                    Picker("Barème", selection: $schedule) {
                        ForEach(SanitizingSchedule.allCases) { schedule in
                            Text(schedule.label).tag(schedule)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    TextField("Enceinte utilisée", text: $equipmentName)
                    DatePicker("Début du traitement", selection: $startedAt, in: ...Date.now)
                } header: {
                    Text("Barème")
                } footer: {
                    Text(schedule.detail)
                }

                Section("Détails") {
                    OperatorField(name: $operatorName)
                    TextField("Commentaire", text: $comment, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle("Traitement assainissant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Démarrer") { save() }
                        .disabled(productName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if operatorName.isEmpty { operatorName = preferences.operatorName }
            }
        }
    }

    private func save() {
        let record = SanitizingFreezeRecord(
            productName: productName.trimmingCharacters(in: .whitespacesAndNewlines),
            batchNumber: batchNumber,
            supplier: supplier,
            intendedUse: intendedUse,
            schedule: schedule,
            startedAt: startedAt,
            equipmentName: equipmentName,
            quantity: quantity,
            operatorName: operatorName,
            comment: comment
        )
        context.insert(record)
        try? context.save()
        dismiss()
    }
}

// MARK: - Clôture

struct SanitizingFreezeFinishView: View {

    @Environment(\.dismiss) private var dismiss

    let record: SanitizingFreezeRecord
    let context: ModelContext

    @State private var finishedAt = Date.now
    @State private var temperatureText = ""
    @State private var comment: String = ""

    private var temperature: Double? {
        AppFormatters.parseTemperature(temperatureText)
    }

    private var scheduleMet: Bool {
        finishedAt.timeIntervalSince(record.startedAt) >= record.schedule.minimumDuration
    }

    private var temperatureReached: Bool {
        guard let temperature else { return false }
        return temperature <= record.schedule.targetTemperature
    }

    private var willBeCompliant: Bool {
        scheduleMet && temperatureReached
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Produit", value: record.displayName)
                    LabeledContent("Barème", value: record.schedule.label)
                    LabeledContent("Démarré le", value: AppFormatters.dateAndTime(record.startedAt))
                }

                Section {
                    DatePicker("Fin du traitement", selection: $finishedAt, in: record.startedAt...Date.now)

                    HStack {
                        Text("Température à cœur")
                        Spacer()
                        TextField("−20,0", text: $temperatureText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                            .frame(maxWidth: 100)
                        Text("°C").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Relevé de clôture")
                } footer: {
                    Text("La température se mesure au cœur du produit, pas dans l'air de l'enceinte.")
                }

                Section {
                    verdictRow(
                        "Durée du barème",
                        detail: formattedDuration,
                        isMet: scheduleMet
                    )
                    verdictRow(
                        "Température atteinte",
                        detail: temperature == nil
                            ? "Non relevée"
                            : "Cible \(AppFormatters.temperature(record.schedule.targetTemperature))",
                        isMet: temperatureReached
                    )
                }

                if !willBeCompliant {
                    Section {
                        TextField(
                            "Que faites-vous de ce lot ?",
                            text: $comment,
                            axis: .vertical
                        )
                        .lineLimit(2...5)
                    } header: {
                        Label("Traitement non conforme", systemImage: "exclamationmark.triangle")
                    } footer: {
                        Text("Un lot qui n'a pas subi le barème complet ne peut pas être servi cru. Il reste consommable après cuisson à cœur — précisez ici ce qui en a été fait.")
                    }
                }

                Section {
                    Button {
                        save()
                    } label: {
                        Label("Clôturer le traitement", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(willBeCompliant ? .green : .orange)
                    .disabled(temperature == nil || (!willBeCompliant && comment.trimmingCharacters(in: .whitespaces).isEmpty))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Clôture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }

    private var formattedDuration: String {
        let total = Int(max(0, finishedAt.timeIntervalSince(record.startedAt)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours) h \(String(format: "%02d", minutes))" : "\(minutes) min"
    }

    private func verdictRow(_ title: String, detail: String, isMet: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isMet ? Color.green : Color.red)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func save() {
        record.finish(at: finishedAt, coreTemperature: temperature)

        if !comment.trimmingCharacters(in: .whitespaces).isEmpty {
            let existing = record.comment.trimmingCharacters(in: .whitespaces)
            record.comment = existing.isEmpty ? comment : existing + "\n" + comment
        }

        try? context.save()
        dismiss()
    }
}
