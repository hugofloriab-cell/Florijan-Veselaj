//
//  AssistantView.swift
//  HACCPPocket
//
//  L'assistant vocal — l'échange, mains libres.
//
//  ─────────────────────────────────────────────────────────────────────────
//  LA BOUCLE
//  ─────────────────────────────────────────────────────────────────────────
//
//  On touche le micro une fois. Ensuite l'écran enchaîne tout seul :
//  il écoute, il répond, et il rouvre le micro. Tant que l'échange n'est pas
//  clos, on ne retouche plus l'écran.
//
//  C'est la raison d'être de cette page. En cuisine on a les mains dans un
//  bac ou dans de la farine ; un assistant qui réclame un appui entre chaque
//  phrase fait perdre plus de temps qu'il n'en fait gagner.
//
//  Le micro ne se rouvre qu'une fois la phrase entièrement prononcée. Sans
//  cela il entendrait le haut-parleur et se répondrait à lui-même.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUI ARRÊTE LA BOUCLE
//  ─────────────────────────────────────────────────────────────────────────
//
//  Trois choses, et rien d'autre : un silence, un mot d'arrêt, ou un accord
//  donné. Le silence compte — sans lui, une cuisine vide relancerait le
//  micro indéfiniment.
//
//  ─────────────────────────────────────────────────────────────────────────
//  L'ACCORD RESTE EXPLICITE
//  ─────────────────────────────────────────────────────────────────────────
//
//  L'assistant récapitule et demande. Rien ne s'ouvre, et surtout rien ne
//  s'écrit, avant un « oui » ou un doigt sur le bouton. Les deux chemins
//  existent : à la voix quand les mains sont prises, au doigt quand le bruit
//  couvre tout.
//

import SwiftUI

struct AssistantView: View {

    /// Le parc réel de l'établissement, fourni par l'écran d'accueil.
    ///
    /// Déclaré avant `onAction` pour que l'appel garde la fermeture en
    /// dernier : `AssistantView(equipment: …) { action in … }`.
    var equipment: [EquipmentBrief] = []

    /// Ce que l'écran rend quand l'accord est donné : à l'appelant d'ouvrir
    /// l'écran correspondant, ou d'écrire au registre. L'assistant ne
    /// navigue pas et n'enregistre pas lui-même : il propose.
    var onAction: (AssistantAction) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dictation = VoiceDictation()
    @State private var conversation = AssistantConversation()
    @State private var narrator = PiperNarrator()
    @State private var intelligence = IntelligenceAvailability.needsNewerSystem

    /// L'échange mains libres est ouvert : le micro se rouvrira seul.
    @State private var isConversing = false

    /// Le diagnostic est replié tant que tout va bien. Il n'a d'intérêt que
    /// le jour où quelque chose manque.
    @State private var showsDiagnostic = false

    /// La voix est un confort : on la coupe d'un geste, et le choix tient.
    @AppStorage("haccp.assistant.voice") private var voiceEnabled = true

    private var everythingWorks: Bool {
        dictation.supportsFrenchOnDevice && intelligence.isReady && narrator.isAvailable
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    diagnostic
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    conversationArea

                    confirmationCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    microphone
                        .padding(.bottom, 24)
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
                    Button("Effacer") { restart() }
                        .disabled(conversation.turns.isEmpty)
                }
            }
            .task {
                intelligence = .current
                // Le parc est donné avant le premier mot : les instructions
                // du modèle le contiennent, et il ne peut donc pas inventer
                // une enceinte qui n'existe pas.
                conversation.load(equipment: equipment)
                // Le modèle de voix pèse soixante mégaoctets : on le charge
                // à l'ouverture de l'écran, pas au premier mot prononcé.
                await narrator.prepare()
            }
            // La dictée s'arrête d'elle-même après un silence. C'est ce
            // moment-là qui fait avancer l'échange — pas un bouton de plus
            // à toucher les mains occupées.
            .onChange(of: dictation.isListening) { wasListening, isListening in
                guard wasListening, !isListening else { return }
                let said = dictation.transcript
                dictation.clear()
                Task { await advance(with: said) }
            }
            .onDisappear {
                isConversing = false
                dictation.stop()
                narrator.stop()
            }
        }
    }

    // MARK: - La boucle

    /// Un tour complet : comprendre, répondre, rouvrir le micro.
    private func advance(with said: String) async {
        // Toucher le bouton pendant qu'on écoute, c'est renoncer. Le micro
        // s'arrête alors comme à la fin d'une phrase, mais `isConversing`
        // est déjà retombé : sans ce garde-fou, l'assistant répondrait à
        // une demande qu'on vient d'annuler.
        guard isConversing else { return }

        let text = said.trimmingCharacters(in: .whitespacesAndNewlines)

        // Un silence ferme l'échange. Sans cette porte de sortie, une
        // cuisine vide relancerait le micro sans fin.
        guard !text.isEmpty else {
            isConversing = false
            return
        }

        switch await conversation.send(text) {
        case .speak(let sentence):
            await say(sentence)
            await listenAgain()

        case .confirm(_, let sentence):
            await say(sentence)
            await listenAgain()

        case .act(let action, let sentence):
            await say(sentence)
            isConversing = false
            onAction(action)

        case .stop(let sentence):
            await say(sentence)
            isConversing = false

        case .failed:
            // La raison est déjà affichée par la carte : la répéter à voix
            // haute n'apprendrait rien et couperait la parole.
            isConversing = false
        }
    }

    private func say(_ sentence: String) async {
        guard voiceEnabled, narrator.isAvailable else { return }
        await narrator.speak(sentence)
    }

    /// Rouvre le micro, une fois la phrase terminée.
    private func listenAgain() async {
        guard isConversing else { return }

        // Un court silence laisse retomber le haut-parleur. Sans lui, le
        // micro rattrape la fin de la phrase et l'assistant se répond.
        try? await Task.sleep(for: .milliseconds(350))

        guard isConversing, !dictation.isListening else { return }
        dictation.clear()
        await dictation.start()
    }

    private func beginConversing() {
        isConversing = true
        dictation.clear()
        Task { await dictation.start() }
    }

    private func restart() {
        isConversing = false
        dictation.stop()
        dictation.clear()
        narrator.stop()
        conversation.reset()
    }

    /// L'accord donné au doigt plutôt qu'à la voix.
    private func confirmByTouch(_ action: AssistantAction) {
        isConversing = false
        dictation.stop()
        onAction(action)
    }

    // MARK: - Diagnostic

    /// Une ligne quand tout va bien, le détail quand on le demande.
    ///
    /// Trois lignes permanentes mangeaient la moitié de l'écran pour
    /// répéter chaque fois la même bonne nouvelle. L'échange a besoin de
    /// cette place.
    @ViewBuilder
    private var diagnostic: some View {
        if everythingWorks && !showsDiagnostic {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showsDiagnostic = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Dictée, compréhension et voix : tout fonctionne hors ligne.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
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

                if everythingWorks {
                    Button("Réduire") {
                        withAnimation(.easeInOut(duration: 0.2)) { showsDiagnostic = false }
                    }
                    .font(.caption)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
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

    // MARK: - Le fil de l'échange

    @ViewBuilder
    private var conversationArea: some View {
        if case .unavailable(let reason) = dictation.state {
            messageArea(systemImage: "mic.slash", title: "Dictée impossible", detail: reason)
        } else if conversation.turns.isEmpty && dictation.transcript.isEmpty {
            messageArea(
                systemImage: "bubble.left.and.bubble.right",
                title: dictation.isListening ? "Je vous écoute" : "Touchez le micro et parlez",
                detail: dictation.isListening
                    ? "Parlez normalement, à vingt centimètres."
                    : "Dites par exemple : « j'entame un sac de sucre ». L'assistant vous répondra et rouvrira le micro tout seul."
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(conversation.turns) { turn in
                            bubble(for: turn)
                                .id(turn.id)
                        }

                        // Ce qui est en train d'être dit, avant même que la
                        // phrase soit finie. Voir les mots arriver vaut tous
                        // les voyants : on sait que le micro entend.
                        if !dictation.transcript.isEmpty {
                            bubble(for: .init(speaker: .cook, text: dictation.transcript))
                                .opacity(0.55)
                                .id(Self.pendingBubbleID)
                        }

                        if case .thinking = conversation.phase {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Je réfléchis…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .id(Self.thinkingBubbleID)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: conversation.turns.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(conversation.turns.last?.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private static let pendingBubbleID = "en-cours"
    private static let thinkingBubbleID = "reflexion"

    private func bubble(for turn: AssistantConversation.Turn) -> some View {
        HStack {
            if turn.speaker == .cook { Spacer(minLength: 40) }

            Text(turn.text)
                .font(.callout)
                .foregroundStyle(turn.speaker == .cook ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    turn.speaker == .cook ? Color.brand : Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .fixedSize(horizontal: false, vertical: true)

            if turn.speaker == .assistant { Spacer(minLength: 40) }
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

    // MARK: - L'accord

    /// La carte n'apparaît qu'au moment de décider.
    ///
    /// Elle double la voix sans la remplacer : « oui » suffit quand les
    /// mains sont prises, le bouton reste là quand la hotte couvre tout.
    @ViewBuilder
    private var confirmationCard: some View {
        switch conversation.phase {
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

        case .awaitingConfirmation(let action):
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

                Button {
                    confirmByTouch(action)
                } label: {
                    Text(action.actionLabel)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Text("Dites « oui » pour ouvrir, « non » pour corriger.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        case .idle, .thinking, .awaitingDetail:
            EmptyView()
        }
    }

    // MARK: - Le bouton

    private var microphone: some View {
        VStack(spacing: 12) {
            Button {
                if isConversing || dictation.isListening {
                    isConversing = false
                    dictation.stop()
                    narrator.stop()
                } else {
                    beginConversing()
                }
            } label: {
                ZStack {
                    // L'anneau suit la voix. Il ne décore pas : le voir
                    // rester plat pendant qu'on parle, c'est comprendre
                    // aussitôt que le micro est couvert.
                    Circle()
                        .fill(Color.brand.opacity(0.18))
                        .frame(width: 108, height: 108)
                        .scaleEffect(reduceMotion ? 1 : 1 + dictation.level * 0.45)
                        .animation(.easeOut(duration: 0.12), value: dictation.level)
                        .opacity(dictation.isListening ? 1 : 0)

                    Circle()
                        .fill(circleColor)
                        .frame(width: 92, height: 92)

                    Image(systemName: circleSymbol)
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: 160, height: 130)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isConversing ? "Arrêter l'échange" : "Parler à l'assistant")

            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(height: 34)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var circleColor: Color {
        if dictation.isListening { return .red }
        if narrator.isSpeaking { return .green }
        return .brand
    }

    private var circleSymbol: String {
        if dictation.isListening { return "stop.fill" }
        if narrator.isSpeaking { return "speaker.wave.2.fill" }
        return "mic.fill"
    }

    private var caption: String {
        if narrator.isSpeaking {
            return "Je parle. Le micro se rouvre tout seul après."
        }
        if dictation.isListening {
            return "Je vous écoute.\nS'arrête seul après un silence."
        }
        if case .awaitingConfirmation = conversation.phase {
            return "Rien n'est enregistré tant que vous n'avez pas confirmé."
        }
        if conversation.turns.isEmpty {
            return "Tout se passe sur l'iPhone, sans réseau."
        }
        return "Touchez le micro pour reprendre."
    }
}

#Preview {
    AssistantView()
}
