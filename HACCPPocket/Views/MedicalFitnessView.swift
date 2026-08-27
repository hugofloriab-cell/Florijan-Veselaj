//
//  MedicalFitnessView.swift
//  HACCPPocket
//
//  Suivi médical du personnel.
//

import SwiftUI
import SwiftData
import PhotosUI

#if canImport(UIKit)
import UIKit
#endif

struct MedicalFitnessListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \MedicalFitnessRecord.examinedAt, order: .reverse)
    private var records: [MedicalFitnessRecord]

    @State private var isCreating = false
    @State private var editedRecord: MedicalFitnessRecord?
    @State private var showsPaywall = false

    /// Une personne de l'équipe et l'ensemble de ses visites.
    struct TeamMember: Identifiable {
        let id: String
        let firstName: String
        let fullName: String
        let visits: [MedicalFitnessRecord]

        /// La visite qui décide de l'état affiché : la plus récente.
        var latest: MedicalFitnessRecord? { visits.first }

        var needsAction: Bool { latest?.needsAction ?? true }

        var statusLabel: String { latest?.statusLabel ?? "Aucune visite" }
    }

    /// Regroupe les fiches par personne, la plus récente visite en tête.
    ///
    /// Assemblé en deux temps plutôt qu'en une expression : un `Dictionary`
    /// suivi d'un `map` et d'un tri imbriqués est exactement le genre de
    /// chaîne que le compilateur met une éternité à résoudre.
    private var team: [TeamMember] {
        var grouped: [String: [MedicalFitnessRecord]] = [:]

        for record in records {
            grouped[record.personKey, default: []].append(record)
        }

        var members: [TeamMember] = []

        for (key, visits) in grouped {
            let sorted = visits.sorted { $0.examinedAt > $1.examinedAt }
            guard let reference = sorted.first else { continue }

            members.append(
                TeamMember(
                    id: key,
                    firstName: reference.firstName,
                    fullName: reference.displayName,
                    visits: sorted
                )
            )
        }

        return members.sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
    }

    private var attention: [TeamMember] { team.filter(\.needsAction) }
    private var upToDate: [TeamMember] { team.filter { !$0.needsAction } }

    var body: some View {
        List {
            Section {
                Label(
                    "Une personne atteinte d'une maladie transmissible par les aliments ne doit pas manipuler de denrées. Le suivi médical qui permet de s'en assurer relève de la médecine du travail.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if records.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Aucun suivi enregistré", systemImage: "stethoscope")
                    } description: {
                        Text("Archivez ici les attestations de suivi et les avis d'aptitude délivrés par le service de santé au travail, et voyez venir les échéances.")
                    } actions: {
                        Button("Enregistrer un suivi") { create() }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if !attention.isEmpty {
                Section {
                    ForEach(attention) { member in memberRow(member) }
                } header: {
                    Text("À traiter")
                } footer: {
                    Text("Visite dépassée, à prévoir, ou avis appelant une décision de votre part.")
                }
            }

            if !upToDate.isEmpty {
                Section("À jour") {
                    ForEach(upToDate) { member in memberRow(member) }
                }
            }
        }
        .navigationTitle("Suivi médical")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { create() } label: {
                    Label("Enregistrer un suivi", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            MedicalFitnessEditorView(record: nil, context: modelContext)
        }
        .sheet(item: $editedRecord) { record in
            MedicalFitnessEditorView(record: record, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }

    /// Une personne de l'équipe : prénom en tête, état de son suivi.
    private func memberRow(_ member: MedicalFitnessListView.TeamMember) -> some View {
        NavigationLink {
            MedicalPersonView(
                firstName: member.firstName,
                fullName: member.fullName,
                visits: member.visits
            )
        } label: {
            HStack(spacing: 12) {
                RowIcon(
                    systemImage: "person.crop.circle",
                    tint: member.needsAction ? .orange : .brand
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(member.firstName)
                        .font(.subheadline.weight(.semibold))

                    if let latest = member.latest {
                        Text("Dernière visite le \(AppFormatters.shortDate(latest.examinedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let next = latest.nextVisitDate {
                            Text("Prochaine le \(AppFormatters.shortDate(next))")
                                .font(.caption2)
                                .foregroundStyle(latest.isOverdue() ? Color.orange : Color.secondary)
                        }
                    }
                }

                Spacer(minLength: 8)

                StatusBadge(
                    text: member.statusLabel,
                    color: member.needsAction ? .orange : .green
                )
            }
            .padding(.vertical, 4)
        }
    }

    private func create() {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        isCreating = true
    }

}

// MARK: - Le dossier d'une personne

/// Les visites d'un membre de l'équipe.
///
/// ─────────────────────────────────────────────────────────────────────────
/// POURQUOI LE CONTENU EST MASQUÉ PAR DÉFAUT
/// ─────────────────────────────────────────────────────────────────────────
///
/// L'avis d'aptitude et ses restrictions relèvent du suivi médical du
/// salarié. L'employeur les détient parce qu'il doit les appliquer, pas pour
/// les afficher. Un écran qui étale « inapte au poste » à côté d'un prénom,
/// devant qui passe dans la cuisine, transforme un document de travail en
/// affichage public.
///
/// L'écran montre donc par défaut ce qui suffit à gérer : la visite a eu
/// lieu, à telle date, la suivante est prévue à telle autre. Le contenu ne
/// s'ouvre que sur un geste délibéré, précédé d'un avertissement.
struct MedicalPersonView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    let firstName: String
    let fullName: String
    let visits: [MedicalFitnessRecord]

    @State private var isRevealed = false
    @State private var editedRecord: MedicalFitnessRecord?
    @State private var isCreating = false
    @State private var showsPaywall = false

    var body: some View {
        List {
            Section {
                InfoRow(label: "Nom complet", value: fullName, systemImage: "person.text.rectangle")
                if let latest = visits.first, !latest.jobTitle.isEmpty {
                    InfoRow(label: "Poste", value: latest.jobTitle, systemImage: "briefcase")
                }
                if let latest = visits.first, !latest.occupationalHealthService.isEmpty {
                    InfoRow(
                        label: "Service de santé au travail",
                        value: latest.occupationalHealthService,
                        systemImage: "cross.case"
                    )
                }
            }

            confidentialitySection

            Section {
                ForEach(visits) { visit in
                    visitRow(visit)
                }
            } header: {
                Text("Visites")
            } footer: {
                Text("Le registre mensuel ne reprend que la mention « visite effectuée » ou « non effectuée ». Le contenu de l'avis n'en sort jamais.")
            }
        }
        .navigationTitle(firstName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    guard subscription.canWrite else { showsPaywall = true; return }
                    isCreating = true
                } label: {
                    Label("Nouvelle visite", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            MedicalFitnessEditorView(record: nil, context: modelContext)
        }
        .sheet(item: $editedRecord) { record in
            MedicalFitnessEditorView(record: record, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }

    private var hasConfidentialContent: Bool {
        visits.contains(\.hasConfidentialContent)
    }

    @ViewBuilder
    private var confidentialitySection: some View {
        if hasConfidentialContent {
            Section {
                Toggle(isOn: $isRevealed) {
                    Label(
                        isRevealed ? "Contenu affiché" : "Afficher le contenu du dossier",
                        systemImage: isRevealed ? "eye" : "eye.slash"
                    )
                }
            } header: {
                Text("Confidentialité")
            } footer: {
                Text("L'avis d'aptitude et ses restrictions éventuelles relèvent du suivi médical de la personne. Ne les affichez que si vous en avez besoin, et jamais devant un tiers qui n'a pas à en connaître — un contrôleur qui les demande doit le formuler explicitement.")
            }
        }
    }

    private func visitRow(_ visit: MedicalFitnessRecord) -> some View {
        Button {
            guard subscription.canWrite else { showsPaywall = true; return }
            editedRecord = visit
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(
                    systemImage: "calendar",
                    tint: visit.isOverdue() ? .orange : .brand
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Visite du \(AppFormatters.shortDate(visit.examinedAt))")
                        .font(.subheadline.weight(.medium))

                    if let next = visit.nextVisitDate {
                        Text("Prochaine le \(AppFormatters.shortDate(next))")
                            .font(.caption)
                            .foregroundStyle(visit.isOverdue() ? Color.orange : Color.secondary)
                    }

                    // Le contenu, et lui seul, est derrière l'interrupteur.
                    if isRevealed {
                        Text(visit.verdict.label)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(visit.verdict.needsAttention ? Color.orange : Color.green)

                        if !visit.restrictions.isEmpty {
                            Text(visit.restrictions)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Spacer(minLength: 8)

                if visit.hasDocument {
                    Image(systemName: "paperclip")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                guard subscription.canWrite else { showsPaywall = true; return }
                modelContext.delete(visit)
                try? modelContext.save()
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }
}

// MARK: - Éditeur

struct MedicalFitnessEditorView: View {

    @Environment(\.dismiss) private var dismiss

    private let record: MedicalFitnessRecord?
    private let context: ModelContext

    @State private var personName: String
    @State private var jobTitle: String
    @State private var service: String
    @State private var examinedAt: Date
    @State private var hasNextVisit: Bool
    @State private var nextVisitDate: Date
    @State private var verdict: FitnessVerdict
    @State private var restrictions: String
    @State private var comment: String
    @State private var documentData: Data?
    @State private var documentItem: PhotosPickerItem?

    init(record: MedicalFitnessRecord?, context: ModelContext) {
        self.record = record
        self.context = context

        _personName = State(initialValue: record?.personName ?? "")
        _jobTitle = State(initialValue: record?.jobTitle ?? "")
        _service = State(initialValue: record?.occupationalHealthService ?? "")
        _examinedAt = State(initialValue: record?.examinedAt ?? .now)
        _hasNextVisit = State(initialValue: record?.nextVisitDate != nil)
        _nextVisitDate = State(
            initialValue: record?.nextVisitDate
                ?? Calendar.current.date(byAdding: .year, value: 2, to: .now)
                ?? .now
        )
        _verdict = State(initialValue: record?.verdict ?? .fit)
        _restrictions = State(initialValue: record?.restrictions ?? "")
        _comment = State(initialValue: record?.comment ?? "")
        _documentData = State(initialValue: record?.documentData)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Personne") {
                    OperatorField(name: $personName, placeholder: "Nom et prénom")
                    TextField("Poste occupé", text: $jobTitle)
                }

                Section {
                    DatePicker("Date de la visite", selection: $examinedAt, in: ...Date.now, displayedComponents: .date)
                    TextField("Service de santé au travail", text: $service)

                    Toggle("Prochaine visite programmée", isOn: $hasNextVisit)
                    if hasNextVisit {
                        DatePicker("Prochaine visite", selection: $nextVisitDate, displayedComponents: .date)
                    }
                } header: {
                    Text("Visite")
                } footer: {
                    Text("La périodicité dépend du poste et du service de santé au travail : elle n'est pas la même pour tout le monde. Reportez la date que votre service vous a indiquée.")
                }

                Section {
                    Picker("Avis", selection: $verdict) {
                        ForEach(FitnessVerdict.allCases) { verdict in
                            Label(verdict.label, systemImage: verdict.systemImage).tag(verdict)
                        }
                    }

                    if verdict != .fit {
                        TextField(
                            "Aménagements ou restrictions prononcés",
                            text: $restrictions,
                            axis: .vertical
                        )
                        .lineLimit(2...5)
                    }
                } header: {
                    Text("Avis rendu")
                }

                documentSection

                Section("Détails") {
                    TextField("Commentaire", text: $comment, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle(record == nil ? "Nouveau suivi" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(personName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var documentSection: some View {
        Section {
            #if canImport(UIKit)
            if let documentData, let image = UIImage(data: documentData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button(role: .destructive) {
                    self.documentData = nil
                } label: {
                    Label("Retirer le document", systemImage: "trash")
                }
            }
            #endif

            PhotosPicker(selection: $documentItem, matching: .images) {
                Label(
                    documentData == nil ? "Photographier l'attestation" : "Remplacer le document",
                    systemImage: "doc.viewfinder"
                )
            }
        } header: {
            Text("Attestation")
        } footer: {
            Text("L'employeur tient ces documents à disposition. Les conserver ici évite de fouiller un classeur le jour où on les demande.")
        }
        .onChange(of: documentItem) { _, item in
            Task { await loadDocument(item) }
        }
    }

    private func loadDocument(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            documentData = data
        }
    }

    private func save() {
        let target = record ?? MedicalFitnessRecord()

        target.personName = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.jobTitle = jobTitle
        target.occupationalHealthService = service
        target.examinedAt = examinedAt
        target.nextVisitDate = hasNextVisit ? nextVisitDate : nil
        target.verdict = verdict
        target.restrictions = verdict == .fit ? "" : restrictions
        target.documentData = documentData
        target.comment = comment

        if record == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}
