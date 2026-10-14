//
//  AssistantView.swift
//  HACCPPocket
//
//  L'assistant vocal — première étape : entendre.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUE CET ÉCRAN FAIT, ET CE QU'IL NE FAIT PAS ENCORE
//  ─────────────────────────────────────────────────────────────────────────
//
//  Il écoute et il écrit. Il ne comprend rien, et n'ouvre aucun onglet : ça
//  viendra ensuite. Il est livré seul parce qu'il répond à la seule question
//  qui décide du reste — est-ce que la dictée tient en cuisine, hotte
//  allumée, à bout de bras, avec l'accent du coin ?
//
//  Il affiche donc aussi un diagnostic : reconnaissance locale ou non,
//  modèle de langage disponible ou non. De quoi savoir, avant d'écrire la
//  suite, sur quels appareils elle fonctionnera.
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

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dictation = VoiceDictation()
    @State private var intelligence = IntelligenceAvailability.needsNewerSystem

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    diagnostic
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    transcriptArea

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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Effacer") { dictation.clear() }
                        .disabled(dictation.transcript.isEmpty)
                }
            }
            .task { intelligence = .current }
            .onDisappear { dictation.stop() }
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
                detail: intelligence.advice ?? "La compréhension des phrases arrivera à la prochaine étape.",
                isGood: intelligence.isReady
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
        return "Touchez le micro pour dicter à nouveau."
    }
}

#Preview {
    AssistantView()
}
