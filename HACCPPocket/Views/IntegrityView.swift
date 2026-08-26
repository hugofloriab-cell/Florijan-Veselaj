//
//  IntegrityView.swift
//  HACCPPocket
//
//  Scellés mensuels et vérification d'intégrité.
//

import SwiftUI
import SwiftData

struct IntegrityListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(UserPreferences.self) private var preferences
    @Environment(SubscriptionManager.self) private var subscription

    /// Le mode consultation affiche les scellés mais ne permet pas d'en créer.
    var isReadOnly: Bool = false

    @Query(sort: \IntegritySeal.sequence, order: .reverse)
    private var seals: [IntegritySeal]

    @State private var verdicts: [PersistentIdentifier: IntegrityVerdict] = [:]
    @State private var isVerifying = false
    @State private var monthToSeal: Date = .now
    @State private var showsSealConfirmation = false
    @State private var showsPaywall = false
    @State private var errorMessage: String?

    /// Mois précédent : celui qu'on clôture normalement.
    private var suggestedMonth: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    }

    var body: some View {
        List {
            explanationSection

            if !isReadOnly {
                sealSection
            }

            if seals.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Aucun mois clôturé", systemImage: "checkmark.seal")
                    } description: {
                        Text("Clôturer un mois enregistre une empreinte de ses données. La recalculer plus tard permet de démontrer qu'aucun enregistrement n'a bougé depuis.")
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(seals) { seal in
                        row(seal)
                    }
                } header: {
                    Text("Mois clôturés")
                } footer: {
                    Text("Chaque scellé reprend l'empreinte du précédent. Retirer un mois de la suite casse la chaîne, et cela se voit.")
                }

                Section {
                    Button {
                        verifyAll()
                    } label: {
                        if isVerifying {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Vérification…")
                            }
                        } else {
                            Label("Vérifier tous les scellés", systemImage: "checkmark.shield")
                        }
                    }
                    .disabled(isVerifying)
                }
            }
        }
        .navigationTitle("Intégrité")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Clôturer ce mois ?", isPresented: $showsSealConfirmation) {
            Button("Clôturer") { seal(monthToSeal) }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("L'empreinte des enregistrements de \(AppFormatters.monthTitle(monthToSeal)) sera calculée et conservée. Vous pourrez continuer à saisir, mais toute modification postérieure deviendra détectable.")
        }
        .alert("Intégrité", isPresented: errorBinding, presenting: errorMessage) { _ in
            Button("Fermer", role: .cancel) { errorMessage = nil }
        } message: { message in
            Text(message)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }

    // MARK: - Explication

    private var explanationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Ce que garantit ce mécanisme", systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold))

                Text("Il rend toute modification **détectable**, pas impossible. Aucune application installée sur votre appareil ne peut empêcher qu'on y modifie des données : celui qui contrôle le téléphone contrôle la base.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("En revanche, un registre scellé chaque mois et vérifiable est bien plus solide qu'un classeur papier — que personne n'a jamais prétendu infalsifiable non plus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Clôture

    private var sealSection: some View {
        Section {
            DatePicker(
                "Mois à clôturer",
                selection: $monthToSeal,
                in: ...Date.now,
                displayedComponents: .date
            )

            Button {
                guard subscription.canWrite else {
                    showsPaywall = true
                    return
                }
                showsSealConfirmation = true
            } label: {
                Label("Clôturer le mois", systemImage: "lock.doc")
            }
        } header: {
            Text("Clôturer un mois")
        } footer: {
            Text("On clôture en général le mois précédent, une fois toutes les saisies faites.")
        }
        .onAppear {
            if seals.isEmpty { monthToSeal = suggestedMonth }
        }
    }

    // MARK: - Ligne

    private func row(_ seal: IntegritySeal) -> some View {
        let verdict = verdicts[seal.persistentModelID]

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(
                    systemImage: verdict.map { $0.isIntact ? "checkmark.seal.fill" : "exclamationmark.triangle.fill" } ?? "seal",
                    tint: verdict.map { $0.isIntact ? Color.green : Color.red } ?? .secondary
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(seal.periodLabel)
                        .font(.subheadline.weight(.medium))
                    Text("Clôturé le \(AppFormatters.dateAndTime(seal.sealedAt)) · \(seal.recordCount) enregistrement(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Empreinte \(seal.shortDigest)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                if let verdict {
                    StatusBadge(
                        text: verdict.title,
                        color: verdict.isIntact ? .green : .red
                    )
                }
            }

            if let verdict, !verdict.isIntact {
                Text(verdict.detail)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 44)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func seal(_ month: Date) {
        do {
            try IntegrityService.seal(
                monthContaining: month,
                in: modelContext,
                sealedBy: preferences.operatorName
            )
        } catch {
            errorMessage = "La clôture a échoué. \(error.localizedDescription)"
        }
    }

    private func verifyAll() {
        isVerifying = true

        Task { @MainActor in
            await Task.yield()

            var results: [PersistentIdentifier: IntegrityVerdict] = [:]
            for seal in seals {
                do {
                    results[seal.persistentModelID] = try IntegrityService.verify(
                        seal,
                        in: modelContext,
                        allSeals: seals
                    )
                } catch {
                    errorMessage = "La vérification a échoué. \(error.localizedDescription)"
                    break
                }
            }

            verdicts = results
            isVerifying = false
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
