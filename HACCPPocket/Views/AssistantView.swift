//
//  AssistantView.swift
//  HACCPPocket
//
//  L'assistant vocal — première étape : entendre.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUE CET ÉCRAN FAIT, ET OÙ IL S'ARRÊTE
//  ─────────────────────────────────────────────────────────────────────────
//
//  Il écoute, il comprend l'intention, et il propose d'ouvrir l'écran qui
//  convient avec ce qu'il a compris déjà écrit. Il ne va pas plus loin :
//  il n'enregistre rien et ne calcule aucune date.
//
//  Ce qu'il a compris est toujours affiché avant d'agir, et le bouton se
//  touche volontairement. Une application d'hygiène qui enregistrerait sur
//  la foi d'une phrase mal entendue serait pire qu'inutile — elle serait
//  un faux registre.
//
//  Il affiche aussi un diagnostic permanent : reconnaissance locale ou non,
//  modèle disponible ou non. Quand l'une des deux manque, on sait pourquoi.
//
//  ─────────────────────────────────────────────────────────────────────────
//  DESSINÉ POUR UNE MAIN, GRASSE, DANS LE BRUIT
//  ─────────────────────────────────────────────────────────────────────────
//
//  Le bouton fait 108 points et vit en bas de l'écran, dans la zone que le
//  pouce atteint sans changer de prise. On appuie pour lancer, on appuie
//  pour arrêter — pas de maintien, qui obligerait à garder le doigt posé
//  pendant qu'on manipule un bac.
//
//  L'anneau suit le niveau sonore réel. Le voir rester plat pendant qu'on
//  parle, c'est comprendre immédiatement que le micro est couvert — bien
//  plus vite qu'en lisant un message d'erreur.
//

import SwiftUI

struct AssistantView: View {

    /// Ce que l'écran rend quand on valide : à l'appelant d'ouvrir l'écran
    /// correspondant. L'assistant ne navigue pas lui-même, il propose.
    var onAction: (AssistantAction) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dictation = VoiceDictation()
    @State private var understanding = AssistantUnderstanding()
    @State private var narrator = PiperNarrator()
    @State private var intelligence = IntelligenceAvailability.needsNewerSystem

    /// La voix est un confort : on la coupe d'un geste, et le choix tient.
    @AppStorage("haccp.assistant.voice") private var voiceEnabled = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    diagnostic
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    transcriptArea

                    understandingCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    microphone
                        .padding(.bottom, 28)
                }
            }
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        voiceEnabled.toggle()
                        if !voiceEnabled { narrator.stop() }
                    } label: {
                        Image(systemName: voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                    .disabled(!narrator.isAvailable)
                    .accessibilityLabel(voiceEnabled ? "Couper la voix" : "Activer la voix")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Effacer") {
                        dictation.clear()
                        understanding.reset()
                    }
                        .disabled(dictation.transcript.isEmpty)
                }
            }
            .task {
                intelligence = .current
                // Le chargement du modèle prend un instant : on le lance dès
                // l'ouverture de l'écran, pas au premier mot prononcé.
                await narrator.prepare()
            }
            // La dictée s'arrête d'elle-même après un silence : c'est ce
            // moment-là qui déclenche la compréhension, pas un bouton de
            // plus à toucher les mains occupées.
            .onChange(of: dictation.isListening) { wasListening, isListening in
                guard wasListening, !isListening else { return }
                let text = dictation.transcript
                Task { await understanding.interpret(text) }
            }
            // L'assistant répond dès qu'il a compris, jamais avant : parler
            // pendant qu'on réfléchit ne rassure personne.
            .onChange(of: understanding.outcome) { _, outcome in
                guard voiceEnabled, case .understood(let action) = outcome else { return }
                Task { await narrator.speak(action.spokenConfirmation) }
            }
            .onDisappear {
                dictation.stop()
                narrator.stop()
            }
        }
    }

    // MARK: - Diagnostic

    /// Deux lignes qui disent où on en est, sans jargon et sans mentir.
    private var diagnostic: some View {
        VStack(alignment: .leading, spacing: 10) {
            diagnosticRow(
                systemImage: dictation.supportsFrenchOnDevice ? "waveform.badge.mic" : "exclamationmark.triangle",
                title: dictation.supportsFrenchOnDevice
                    ? "Dictée française hors ligne"
                    : "Dictée hors ligne indisponible",
                detail: dictation.supportsFrenchOnDevice
                    ? "Rien ne sort de l'appareil."
                    : "Le modèle français local n'est pas installé sur cet iPhone.",
                isGood: dictation.supportsFrenchOnDevice
            )

            Divider()

            diagnosticRow(
                systemImage: intelligence.systemImage,
                title: intelligence.summary,
                detail: intelligence.advice ?? "Les phrases sont comprises sur l'appareil.",
                isGood: intelligence.isReady
            )

            Divider()

            diagnosticRow(
                systemImage: narrator.isAvailable ? "waveform.circle" : "speaker.slash",
                title: narrator.isAvailable ? "Voix française embarquée" : "Voix indisponible",
                detail: narrator.unavailableReason
                    ?? "L'assistant répond à voix haute. Le haut-parleur en haut à gauche la coupe.",
                isGood: narrator.isAvailable
            )
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func diagnosticRow(
        systemImage: String,
        title: String,
        detail: String,
        isGood: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(isGood ? Color.green : Color.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Ce qui a été entendu

    @ViewBuilder
    private var transcriptArea: some View {
        if case .unavailable(let reason) = dictation.state {
            messageArea(systemImage: "mic.slash", title: "Dictée impossible", detail: reason)
        } else if dictation.transcript.isEmpty {
            messageArea(
                systemImage: "text.bubble",
                title: dictation.isListening ? "Je vous écoute" : "Touchez le micro",
                detail: dictation.isListening
                    ? "Parlez normalement, à vingt centimètres."
                    : "Dites par exemple : « j'entame un sac de sucre en poudre d'un kilo »."
            )
        } else {
            ScrollView {
                Text(dictation.transcript)
                    .font(.title3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .defaultScrollAnchor(.bottom)
        }
    }

    private func messageArea(systemImage: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.headline)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Ce qui a été compris

    /// La proposition, à valider d'un geste délibéré.
    ///
    /// Elle affiche ce qui a été compris avant d'agir — on doit pouvoir
    /// démentir. Un registre d'hygiène rempli sur une phrase mal entendue
    /// ne serait pas un gain de temps, ce serait un faux.
    @ViewBuilder
    private var understandingCard: some View {
        switch understanding.outcome {
        case .idle:
            EmptyView()

        case .thinking:
            HStack(spacing: 10) {
                ProgressView()
                Text("Je réfléchis…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        case .failed(let reason):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        case .understood(let action):
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: action.systemImage)
                        .font(.title3)
                        .foregroundStyle(Color.brand)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .font(.headline)
                        if let detail = action.detail {
                            Text(detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }

                if action.isActionable {
                    Button {
                        onAction(action)
                    } label: {
                        Text(action.actionLabel)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Essayez par exemple : « j'entame un kilo de pâtes », « je relève les températures », « je fais le nettoyage ».")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Le bouton

    private var microphone: some View {
        VStack(spacing: 12) {
            Button {
                if dictation.isListening {
                    dictation.stop()
                } else {
                    Task { await dictation.start() }
                }
            } label: {
                ZStack {
                    // L'anneau suit la voix. Il ne décore pas : il prouve que
                    // le micro entend quelque chose.
                    Circle()
                        .fill(Color.brand.opacity(0.18))
                        .frame(width: 108, height: 108)
                        .scaleEffect(reduceMotion ? 1 : 1 + dictation.level * 0.45)
                        .animation(.easeOut(duration: 0.12), value: dictation.level)
                        .opacity(dictation.isListening ? 1 : 0)

                    Circle()
                        .fill(dictation.isListening ? Color.red : Color.brand)
                        .frame(width: 92, height: 92)

                    Image(systemName: dictation.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: 160, height: 130)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(dictation.isListening ? "Arrêter la dictée" : "Démarrer la dictée")

            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(height: 34)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var caption: String {
        if dictation.isListening {
            return "Touchez pour arrêter.\nS'arrête seul après deux secondes de silence."
        }
        if dictation.transcript.isEmpty {
            return "Tout se passe sur l'iPhone, sans réseau."
        }
        if case .understood = understanding.outcome {
            return "Rien n'est enregistré tant que vous n'avez pas validé."
        }
        return "Touchez le micro pour dicter à nouveau."
    }
}

#Preview {
    AssistantView()
}
