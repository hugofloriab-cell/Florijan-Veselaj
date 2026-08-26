//
//  CorrectiveActionFlowView.swift
//  HACCPPocket
//
//  Le déroulé guidé d'une action corrective.
//
//  Une question par écran, des réponses fermées, et à l'arrivée une conduite
//  à tenir explicite plus la phrase qui part au registre. L'utilisateur n'a
//  jamais à savoir ce qu'il faut écrire : il a seulement à dire ce qu'il voit.
//

import SwiftUI

struct CorrectiveActionFlowView: View {

    let equipment: Equipment
    let measured: Double

    /// Appelé quand l'utilisateur confirme avoir exécuté la conduite à tenir.
    let onComplete: (CorrectiveConclusion) -> Void

    @State private var path: [CorrectiveStep] = []
    @State private var conclusion: CorrectiveConclusion?

    private var currentStep: CorrectiveStep {
        path.last ?? CorrectiveActionGuide.tree(for: equipment, measured: measured)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.gutter) {
                contextBanner

                if let conclusion {
                    conclusionCard(conclusion)
                } else {
                    questionCard(currentStep)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .readableWidth()
        }
        .background(Color(.systemGroupedBackground))
        .animation(.snappy, value: path.count)
        .animation(.snappy, value: conclusion)
        .safeAreaInset(edge: .bottom) {
            if conclusion == nil && !path.isEmpty {
                Button {
                    path.removeLast()
                } label: {
                    Label("Question précédente", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .background(.bar)
            }
        }
    }

    // MARK: - Rappel du contexte

    private var contextBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(equipment.name)
                    .font(.subheadline.weight(.semibold))
                Text("\(AppFormatters.temperature(measured)) relevé, plage attendue \(equipment.formattedRange)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            Color.red.opacity(0.10),
            in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
        )
    }

    // MARK: - Une question

    private func questionCard(_ step: CorrectiveStep) -> some View {
        VStack(alignment: .leading, spacing: DS.gutter) {
            VStack(alignment: .leading, spacing: 6) {
                Text(step.question)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                if let help = step.help {
                    Text(help)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(step.options) { option in
                optionButton(option)
            }
        }
    }

    private func optionButton(_ option: CorrectiveOption) -> some View {
        Button {
            choose(option)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: option.systemImage)
                    .font(.title3)
                    .foregroundStyle(.brand)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(option.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .cardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func choose(_ option: CorrectiveOption) {
        switch option.outcome {
        case .next(let step):
            path.append(step)
        case .conclusion(let reached):
            conclusion = reached
        }
    }

    // MARK: - La conduite à tenir

    private func conclusionCard(_ conclusion: CorrectiveConclusion) -> some View {
        VStack(alignment: .leading, spacing: DS.gutter) {

            HStack(spacing: 12) {
                Image(systemName: conclusion.severity.systemImage)
                    .font(.title)
                    .foregroundStyle(tint(for: conclusion.severity))

                Text(conclusion.title)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(conclusion.instructions.enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(tint(for: conclusion.severity), in: Circle())

                        Text(instruction)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()

            if let note = conclusion.note {
                noteCard(note)
            }

            recordedActionCard(conclusion)

            Button {
                onComplete(conclusion)
            } label: {
                Label("J'ai fait le nécessaire", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint(for: conclusion.severity))

            Button {
                // Se tromper de réponse doit coûter un appui, pas la sortie
                // de l'écran : on repart de la première question.
                self.conclusion = nil
                path.removeAll()
            } label: {
                Text("Je me suis trompé, reprendre")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
    }

    private func noteCard(_ note: RegulatoryNote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.brand)
                Text(note.title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                RegulatoryBadge(note: note)
            }

            Text(note.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.brand.opacity(0.08),
            in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
        )
    }

    private func recordedActionCard(_ conclusion: CorrectiveConclusion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Ce qui sera inscrit au registre", systemImage: "text.append")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(conclusion.recordedAction)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func tint(for severity: CorrectiveSeverity) -> Color {
        switch severity {
        case .recoverable: .green
        case .watch:       .orange
        case .discard:     .red
        }
    }
}
