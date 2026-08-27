//
//  TechnicalIncidentView.swift
//  HACCPPocket
//
//  Déclarer une panne et la transmettre à qui peut agir.
//

import SwiftUI
import SwiftData
import PhotosUI
import MessageUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Liste

struct TechnicalIncidentListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscription

    @Query(sort: \TechnicalIncident.reportedAt, order: .reverse)
    private var incidents: [TechnicalIncident]

    @State private var isCreating = false
    @State private var editedIncident: TechnicalIncident?
    @State private var showsPaywall = false

    /// Les pannes ouvertes, les plus urgentes d'abord.
    private var open: [TechnicalIncident] {
        incidents
            .filter { !$0.isResolved }
            .sorted { left, right in
                if left.severity.sortWeight != right.severity.sortWeight {
                    return left.severity.sortWeight < right.severity.sortWeight
                }
                return left.reportedAt > right.reportedAt
            }
    }

    private var resolved: [TechnicalIncident] {
        incidents.filter(\.isResolved)
    }

    var body: some View {
        List {
            Section { ProtocolLink(procedure: .technicalIncident) }

            if incidents.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Aucune panne déclarée", systemImage: "wrench.and.screwdriver")
                    } description: {
                        Text("Une chambre froide qui remonte, une hotte qui s'arrête, un lave-vaisselle qui ne chauffe plus : déclarez-le ici et transmettez-le à votre technicien. En contrôle, la déclaration montre que la panne a été vue et traitée.")
                    } actions: {
                        Button("Déclarer une panne") { create() }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if !open.isEmpty {
                Section {
                    ForEach(open) { incident in row(incident) }
                } header: {
                    Text("En cours")
                } footer: {
                    Text("Une panne déclarée mais jamais transmise dort dans le téléphone : elle est signalée « à transmettre » tant que le message n'est pas parti.")
                }
            }

            if !resolved.isEmpty {
                Section("Résolues") {
                    ForEach(resolved) { incident in row(incident) }
                }
            }
        }
        .navigationTitle("Pannes et incidents")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { create() } label: {
                    Label("Déclarer une panne", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            TechnicalIncidentEditorView(incident: nil, context: modelContext)
        }
        .sheet(item: $editedIncident) { incident in
            TechnicalIncidentEditorView(incident: incident, context: modelContext)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }

    private func row(_ incident: TechnicalIncident) -> some View {
        Button {
            editedIncident = incident
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(
                    systemImage: incident.kind.systemImage,
                    tint: tint(for: incident)
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(incident.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(incident.isResolved ? Color.secondary : Color.primary)

                    Text(incident.descriptionText.isEmpty ? incident.kind.label : incident.descriptionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text(AppFormatters.dateAndTime(incident.reportedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    StatusBadge(text: incident.statusLabel, color: tint(for: incident))
                    if incident.hasPhoto {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(incident) } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private func tint(for incident: TechnicalIncident) -> Color {
        if incident.isResolved { return .green }
        switch incident.severity {
        case .blocking: return .red
        case .degraded: return .orange
        case .minor:    return .brand
        }
    }

    private func create() {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        isCreating = true
    }

    private func delete(_ incident: TechnicalIncident) {
        guard subscription.canWrite else {
            showsPaywall = true
            return
        }
        modelContext.delete(incident)
        try? modelContext.save()
    }
}

// MARK: - Éditeur

struct TechnicalIncidentEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferences.self) private var preferences

    @Query private var establishments: [Establishment]

    private let incident: TechnicalIncident?
    private let context: ModelContext

    @State private var kind: IncidentKind
    @State private var severity: IncidentSeverity
    @State private var equipmentName: String
    @State private var descriptionText: String
    @State private var immediateAction: String
    @State private var reportedAt: Date
    @State private var reportedBy: String
    @State private var recipientName: String
    @State private var recipientEmail: String
    @State private var isResolved: Bool
    @State private var resolvedAt: Date
    @State private var resolutionNote: String
    @State private var photoData: Data?

    @State private var photoItem: PhotosPickerItem?
    @State private var isComposing = false
    @State private var mailUnavailable = false

    /// L'enregistrement déjà créé pendant cette session d'édition.
    ///
    /// Transmettre enregistre d'abord, puis marque « transmis » au retour du
    /// courrier : sans cette référence, le second enregistrement recréerait
    /// une déclaration au lieu de compléter la première.
    @State private var createdIncident: TechnicalIncident?

    /// Destinataire habituel, retenu d'une déclaration à l'autre : c'est
    /// presque toujours la même personne, et la retaper à chaque panne est le
    /// meilleur moyen de ne plus rien déclarer.
    @AppStorage("haccp.incident.recipientName") private var storedRecipientName: String = ""
    @AppStorage("haccp.incident.recipientEmail") private var storedRecipientEmail: String = ""

    init(incident: TechnicalIncident?, context: ModelContext) {
        self.incident = incident
        self.context = context

        _kind = State(initialValue: incident?.kind ?? .refrigeration)
        _severity = State(initialValue: incident?.severity ?? .degraded)
        _equipmentName = State(initialValue: incident?.equipmentName ?? "")
        _descriptionText = State(initialValue: incident?.descriptionText ?? "")
        _immediateAction = State(initialValue: incident?.immediateAction ?? "")
        _reportedAt = State(initialValue: incident?.reportedAt ?? .now)
        _reportedBy = State(initialValue: incident?.reportedBy ?? "")
        _recipientName = State(initialValue: incident?.recipientName ?? "")
        _recipientEmail = State(initialValue: incident?.recipientEmail ?? "")
        _isResolved = State(initialValue: incident?.isResolved ?? false)
        _resolvedAt = State(initialValue: incident?.resolvedAt ?? .now)
        _resolutionNote = State(initialValue: incident?.resolutionNote ?? "")
        _photoData = State(initialValue: incident?.photoData)
    }

    private var canSave: Bool {
        !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSend: Bool {
        canSave && recipientEmail.contains("@")
    }

    var body: some View {
        NavigationStack {
            Form {
                natureSection
                descriptionSection
                photoSection
                recipientSection
                resolutionSection
            }
            .navigationTitle(incident == nil ? "Déclarer une panne" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        save()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if reportedBy.isEmpty { reportedBy = preferences.operatorName }
                if recipientName.isEmpty { recipientName = storedRecipientName }
                if recipientEmail.isEmpty { recipientEmail = storedRecipientEmail }
            }
            .sheet(isPresented: $isComposing) {
                MailComposeView(
                    recipients: [recipientEmail],
                    subject: draft.mailSubject,
                    body: draft.mailBody(establishment: establishments.first),
                    attachment: photoData
                ) { sent in
                    if sent { markSent() }
                    isComposing = false
                }
            }
            .alert("Courrier indisponible", isPresented: $mailUnavailable) {
                Button("Fermer", role: .cancel) { }
            } message: {
                Text("Aucun compte de messagerie n'est configuré sur cet appareil. Ajoutez-en un dans Réglages → Mail, ou transmettez la déclaration autrement.")
            }
        }
    }

    // MARK: Sections

    private var natureSection: some View {
        Section {
            Picker("Nature", selection: $kind) {
                ForEach(IncidentKind.allCases) { value in
                    Label(value.label, systemImage: value.systemImage).tag(value)
                }
            }

            Picker("Urgence", selection: $severity) {
                ForEach(IncidentSeverity.allCases) { value in
                    Label(value.label, systemImage: value.systemImage).tag(value)
                }
            }

            TextField("Équipement ou emplacement", text: $equipmentName)
            DatePicker("Constaté le", selection: $reportedAt, in: ...Date.now)
        } header: {
            Text("La panne")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(severity.detail)
                if kind.isFoodCritical {
                    Label(
                        "Une enceinte frigorifique en panne met des denrées en jeu. Relevez la température et notez ce que vous en avez fait.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    private var descriptionSection: some View {
        Section {
            TextField("Ce que vous constatez", text: $descriptionText, axis: .vertical)
                .lineLimit(3...8)

            TextField(
                "Ce que vous avez fait en attendant",
                text: $immediateAction,
                axis: .vertical
            )
            .lineLimit(2...6)

            OperatorField(name: $reportedBy)
        } header: {
            Text("Description")
        } footer: {
            Text("\(kind.reportingHint) La mesure prise en attendant est la partie qui compte en contrôle : elle montre que la panne a été gérée, pas subie.")
        }
    }

    @ViewBuilder
    private var photoSection: some View {
        Section {
            #if canImport(UIKit)
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button(role: .destructive) {
                    self.photoData = nil
                } label: {
                    Label("Retirer la photo", systemImage: "trash")
                }
            }
            #endif

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(
                    photoData == nil ? "Photographier la panne" : "Remplacer la photo",
                    systemImage: "camera"
                )
            }
        } header: {
            Text("Photo")
        } footer: {
            Text("Une photo du thermomètre, du voyant ou de la pièce cassée épargne au technicien un déplacement pour diagnostic. Elle est jointe au message.")
        }
        .onChange(of: photoItem) { _, item in
            Task { await loadPhoto(item) }
        }
    }

    private var recipientSection: some View {
        Section {
            TextField("Nom (technicien, direction…)", text: $recipientName)

            TextField("Adresse électronique", text: $recipientEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                sendReport()
            } label: {
                Label("Transmettre par courriel", systemImage: "paperplane")
            }
            .disabled(!canSend)

            if let sentAt = incident?.sentAt {
                Label(
                    "Transmis le \(AppFormatters.dateAndTime(sentAt))",
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.green)
            }
        } header: {
            Text("Destinataire")
        } footer: {
            Text("L'application n'envoie rien elle-même : elle prépare le message et ouvre votre fenêtre de courrier. Vous appuyez sur « Envoyer », depuis votre propre adresse — le message part de votre boîte, reste dans vos messages envoyés, et le destinataire peut y répondre.")
        }
    }

    private var resolutionSection: some View {
        Section {
            Toggle("Panne résolue", isOn: $isResolved)

            if isResolved {
                DatePicker("Résolue le", selection: $resolvedAt, in: reportedAt...Date.now)
                TextField(
                    "Ce qui a été fait (pièce changée, réglage, intervention…)",
                    text: $resolutionNote,
                    axis: .vertical
                )
                .lineLimit(2...5)
            }
        } header: {
            Text("Résolution")
        } footer: {
            Text("Une panne résolue reste au registre : c'est l'historique de l'équipement, et il sert au carnet d'entretien.")
        }
    }

    // MARK: Actions

    /// Un incident temporaire portant la saisie en cours, pour composer le
    /// message sans avoir à enregistrer d'abord.
    private var draft: TechnicalIncident {
        TechnicalIncident(
            kind: kind,
            severity: severity,
            equipmentName: equipmentName,
            descriptionText: descriptionText,
            immediateAction: immediateAction,
            reportedAt: reportedAt,
            reportedBy: reportedBy,
            recipientName: recipientName,
            recipientEmail: recipientEmail
        )
    }

    private func sendReport() {
        guard MailComposeView.canSendMail else {
            mailUnavailable = true
            return
        }
        // On enregistre avant d'ouvrir la fenêtre : si l'utilisateur quitte
        // l'application depuis le courrier, la déclaration ne doit pas être
        // perdue.
        save()
        isComposing = true
    }

    private func markSent() {
        let target = save()
        target.sentAt = .now
        try? context.save()
        dismiss()
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            photoData = data
        }
    }

    @discardableResult
    private func save() -> TechnicalIncident {
        let target = incident ?? createdIncident ?? TechnicalIncident()

        target.kind = kind
        target.severity = severity
        target.equipmentName = equipmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.descriptionText = descriptionText
        target.immediateAction = immediateAction
        target.reportedAt = reportedAt
        target.reportedBy = reportedBy
        target.recipientName = recipientName
        target.recipientEmail = recipientEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        target.resolvedAt = isResolved ? resolvedAt : nil
        target.resolutionNote = isResolved ? resolutionNote : ""
        target.photoData = photoData

        if incident == nil, createdIncident == nil {
            context.insert(target)
            createdIncident = target
        }

        storedRecipientName = recipientName
        storedRecipientEmail = target.recipientEmail

        try? context.save()
        return target
    }
}
