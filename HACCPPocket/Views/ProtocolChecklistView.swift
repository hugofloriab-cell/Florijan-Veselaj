//
//  ProtocolChecklistView.swift
//  HACCPPocket
//
//  Affichage d'un mode opératoire, cochable.
//
//  Les cases ne sont pas enregistrées : ce n'est pas un registre de plus,
//  c'est un fil qu'on suit quand on est interrompu — et en cuisine, on l'est
//  toutes les deux minutes.
//

import SwiftUI

struct ProtocolChecklistView: View {

    @Environment(\.dismiss) private var dismiss

    let procedure: OperationProtocol

    @State private var completedSteps: Set<String> = []

    private var progress: Double {
        guard !procedure.steps.isEmpty else { return 0 }
        return Double(completedSteps.count) / Double(procedure.steps.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.gutter) {
                    header

                    ForEach(Array(procedure.steps.enumerated()), id: \.element.id) { index, step in
                        stepCard(step, number: index + 1)
                    }

                    if let mistake = procedure.commonMistake {
                        mistakeCard(mistake)
                    }
                }
                .padding(16)
                .readableWidth()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Mode opératoire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !completedSteps.isEmpty {
                        Button("Décocher") { completedSteps.removeAll() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    // MARK: - En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: procedure.systemImage)
                    .font(.title)
                    .foregroundStyle(.brand)

                VStack(alignment: .leading, spacing: 2) {
                    Text(procedure.title)
                        .font(.title3.weight(.bold))
                    Text(procedure.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            ProgressView(value: progress)
                .tint(.brand)

            Text("\(completedSteps.count) sur \(procedure.steps.count) — les cases ne sont pas enregistrées, elles servent juste à ne pas perdre le fil.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: - Une étape

    private func stepCard(_ step: ProtocolStep, number: Int) -> some View {
        let isDone = completedSteps.contains(step.id)

        return Button {
            toggle(step)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isDone ? Color.green : Color.brand.opacity(0.14))
                        .frame(width: 28, height: 28)

                    if isDone {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(number)")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.brand)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(step.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isDone ? Color.secondary : Color.primary)
                            .strikethrough(isDone, color: .secondary)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 0)

                        if let note = step.note {
                            RegulatoryBadge(note: note)
                        }
                    }

                    Text(step.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ step: ProtocolStep) {
        if completedSteps.contains(step.id) {
            completedSteps.remove(step.id)
        } else {
            completedSteps.insert(step.id)
        }
    }

    // MARK: - L'erreur classique

    private func mistakeCard(_ mistake: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text("L'erreur classique")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(mistake)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            Color.orange.opacity(0.10),
            in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
        )
    }
}

// MARK: - Bouton d'accès

/// Ligne à poser dans n'importe quel formulaire pour ouvrir le mode
/// opératoire correspondant.
struct ProtocolLink: View {

    let procedure: OperationProtocol

    @State private var showsProtocol = false

    var body: some View {
        Button {
            showsProtocol = true
        } label: {
            HStack(spacing: 12) {
                RowIcon(systemImage: "list.number", tint: .brand)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Comment faire ?")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(procedure.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showsProtocol) {
            ProtocolChecklistView(procedure: procedure)
        }
    }
}

#Preview {
    ProtocolChecklistView(procedure: .rapidCooling)
}
