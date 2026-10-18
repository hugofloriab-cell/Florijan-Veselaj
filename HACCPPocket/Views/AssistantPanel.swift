//
//  AssistantPanel.swift
//  HACCPPocket
//
//  L'assistant, sur la page d'accueil, sans jamais en sortir.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI TOUT TIENT ICI
//  ─────────────────────────────────────────────────────────────────────────
//
//  L'assistant s'ouvrait dans un écran séparé. Une page blanche recouvrait
//  la page bleue au premier mot, et il fallait la refermer pour revenir.
//  Deux endroits pour une seule conversation : l'un où l'on demande,
//  l'autre où l'on répond.
//
//  Tout se passe désormais au même endroit. La salutation laisse place au
//  fil de l'échange, le micro ne bouge pas, et les cartes du registre
//  restent en dessous. Rien ne s'ouvre, rien ne se referme.
//
//  ─────────────────────────────────────────────────────────────────────────
//  DEUX FAÇONS DE DEMANDER
//  ─────────────────────────────────────────────────────────────────────────
//
//  La voix d'abord : c'est le but, parler au lieu de taper, les mains dans
//  un bac. Mais une hotte à pleine puissance couvre une voix. Le champ de
//  saisie n'est pas un pis-aller : une demande tapée suit exactement le
//  même chemin qu'une demande dite.
//
//  Le micro ne se rouvre seul qu'après une demande parlée. Quelqu'un qui
//  écrit le fait parce que la voix ne passe pas ; lui ouvrir le micro ne
//  capterait que la hotte.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUI ARRÊTE LA BOUCLE
//  ─────────────────────────────────────────────────────────────────────────
//
//  Un silence, un mot d'arrêt, ou un accord donné. Le silence compte : sans
//  lui, une cuisine vide relancerait le micro indéfiniment.
//

import SwiftUI

struct AssistantPanel: View {

    /// Le prénom saisi dans les réglages, s'il y en a un.
    var operatorName: String = ""

    /// Le parc réel, pour que l'assistant n'invente pas d'enceinte.
    var equipment: [EquipmentBrief] = []

    /// Le nom de la personne qui contrôle, repris des réglages. Vide, il
    /// sera demandé — un registre anonyme ne vaut rien.
    var operatorName: String = ""

    /// Comment obtenir le relevé du jour, au moment où on le demande.
    ///
    /// Une fermeture, et non un tableau tout fait : construit à chaque
    /// rendu, un tableau porte un identifiant neuf à chaque fois, ce qui
    /// passait pour un changement, provoquait un nouveau rendu, et bouclait.
    /// Et le relevé doit de toute façon refléter l'état du registre à
    /// l'instant de la question, pas à l'ouverture de la page.
    var makeTemperatureReport: () -> AssistantReport? = { nil }

    /// Ce que l'accueil doit faire une fois l'accord donné : ouvrir un
    /// écran, ou inscrire au registre. L'assistant propose, il n'agit pas.
    var onAction: (AssistantAction) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dictation = VoiceDictation()
    @State private var conversation = AssistantConversation()
    @State private var narrator = PiperNarrator()
    @State private var intelligence = IntelligenceAvailability.needsNewerSystem

    @State private var isConversing = false
    @State private var handsFree = true
    @State private var typed = ""
    @FocusState private var isTyping: Bool

    /// La photo attendue, et le texte qui l'accompagne.
    @State private var captureRequest: String?
    @State private var isPresentingCamera = false

    /// La voix est un confort : on la coupe d'un geste, et le choix tient.
    @AppStorage("haccp.assistant.voice") private var voiceEnabled = true

    private var hasStarted: Bool { !conversation.turns.isEmpty }

    var body: some View {
        VStack(spacing: 16) {
            if hasStarted {
                threadHeader
                thread
            } else {
                greeting
            }

            captureCard
            confirmationCard

            microphone
            field

            if !hasStarted {
                suggestions
            }

            trouble
        }
        .padding(.horizontal, 2)
        .task {
            intelligence = .current
            // Le modèle de voix pèse soixante mégaoctets : on le charge à
            // l'ouverture de la page, pas au premier mot prononcé.
            await narrator.prepare()
        }
        // La dictée s'arrête d'elle-même après un silence. C'est ce
        // moment-là qui fait avancer l'échange, pas un bouton de plus à
        // toucher les mains occupées.
        #if canImport(UIKit)
        .sheet(isPresented: $isPresentingCamera) {
            CameraPicker(
                onCapture: { data in
                    Task { await advance(photo: data) }
                },
                onFinish: { isPresentingCamera = false }
            )
            .ignoresSafeArea()
        }
        #endif
        .onChange(of: dictation.isListening) { wasListening, isListening in
            guard wasListening, !isListening else { return }
            let said = dictation.transcript
            dictation.clear()
            Task { await advance(with: said) }
        }
    }

    // MARK: - La boucle

    private func advance(with said: String) async {
        // Toucher le bouton pendant qu'on écoute, c'est renoncer. Le micro
        // s'arrête alors comme à la fin d'une phrase, mais `isConversing`
        // est déjà retombé.
        guard isConversing else { return }

        let text = said.trimmingCharacters(in: .whitespacesAndNewlines)

        // Un silence ferme l'échange. Sans cette porte de sortie, une
        // cuisine vide relancerait le micro sans fin.
        guard !text.isEmpty else {
            isConversing = false
            return
        }

        await handle(await conversation.send(text))
    }

    /// Ce que l'écran fait de la décision de la conversation.
    private func handle(_ reaction: AssistantConversation.Reaction) async {
        switch reaction {
        case .speak(let sentence):
            await say(sentence)
            await listenAgain()

        case .confirm(_, let sentence):
            await say(sentence)
            await listenAgain()

        case .show(let report):
            // Seule la conclusion est dite. Le détail est à l'écran, et
            // l'échange continue.
            await say(report.spoken)
            await listenAgain()

        case .capture(let prompt):
            // On ne rouvre pas le micro : ce qu'on attend est une photo, et
            // un micro ouvert ne capterait que le bruit du quai pendant
            // qu'on cadre.
            captureRequest = prompt
            await say(prompt)

        case .act(let action, let sentence):
            await say(sentence)
            isConversing = false
            onAction(action)

        case .stop(let sentence):
            await say(sentence)
            isConversing = false

        case .failed:
            isConversing = false
        }
    }

    /// La photo prise, lue, et transformée en proposition.
    private func advance(photo data: Data) async {
        captureRequest = nil
        isConversing = true
        handsFree = false
        await handle(await conversation.receivePhoto(data))
    }

    private func say(_ sentence: String) async {
        guard voiceEnabled, narrator.isAvailable else { return }
        await narrator.speak(sentence)
    }

    private func listenAgain() async {
        guard isConversing, handsFree else { return }

        // Un court silence laisse retomber le haut-parleur. Sans lui, le
        // micro rattrape la fin de la phrase et l'assistant se répond.
        try? await Task.sleep(for: .milliseconds(350))

        guard isConversing, !dictation.isListening else { return }
        dictation.clear()
        await dictation.start()
    }

    private func beginListening() {
        conversation.load(
            equipment: equipment,
            temperatures: makeTemperatureReport(),
            checkedBy: operatorName
        )
        isTyping = false
        handsFree = true
        isConversing = true
        dictation.clear()
        Task { await dictation.start() }
    }

    private func send(_ request: String) {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        conversation.load(
            equipment: equipment,
            temperatures: makeTemperatureReport(),
            checkedBy: operatorName
        )
        typed = ""
        isTyping = false
        handsFree = false
        isConversing = true
        Task { await advance(with: trimmed) }
    }

    private func clearEverything() {
        isConversing = false
        dictation.stop()
        dictation.clear()
        narrator.stop()
        conversation.reset()
        typed = ""
        captureRequest = nil
    }

    // MARK: - En haut : l'accueil, ou l'échange

    private var greeting: some View {
        VStack(spacing: 4) {
            Text(operatorName.isEmpty ? "Bonjour" : "Bonjour \(operatorName)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text("De quoi avez-vous besoin ?")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
        .multilineTextAlignment(.center)
        .padding(.top, 8)
    }

    private var threadHeader: some View {
        HStack {
            Button {
                voiceEnabled.toggle()
                if !voiceEnabled { narrator.stop() }
            } label: {
                Image(systemName: voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .foregroundStyle(.white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(!narrator.isAvailable)
            .accessibilityLabel(voiceEnabled ? "Couper la voix" : "Activer la voix")

            Spacer()

            Button("Effacer", action: clearEverything)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    // MARK: - Le fil

    private var thread: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(conversation.turns) { turn in
                bubble(for: turn)
            }

            // Ce qui est en train d'être dit, avant même que la phrase soit
            // finie. Voir les mots arriver vaut tous les voyants.
            if !dictation.transcript.isEmpty {
                textBubble(for: .init(speaker: .cook, text: dictation.transcript))
                    .opacity(0.6)
            }

            if case .thinking = conversation.phase {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text("Je réfléchis…")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func bubble(for turn: AssistantConversation.Turn) -> some View {
        if let report = turn.report {
            VStack(alignment: .leading, spacing: 8) {
                textBubble(for: turn)
                reportCard(report)
            }
        } else {
            textBubble(for: turn)
        }
    }

    /// Le cuisinier en translucide, l'assistant en blanc plein.
    ///
    /// L'asymétrie est volontaire : ce que dit l'assistant se relit, se
    /// vérifie et se montre, donc il lui faut le fond le plus lisible.
    private func textBubble(for turn: AssistantConversation.Turn) -> some View {
        HStack {
            if turn.speaker == .cook { Spacer(minLength: 36) }

            Text(turn.text)
                .font(.callout)
                .foregroundStyle(turn.speaker == .cook ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    turn.speaker == .cook
                        ? AnyShapeStyle(.white.opacity(0.22))
                        : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .fixedSize(horizontal: false, vertical: true)

            if turn.speaker == .assistant { Spacer(minLength: 36) }
        }
    }

    // MARK: - Montrer plutôt que dire

    /// Le tableau attaché à une réplique.
    ///
    /// Pleine largeur, contrairement aux bulles : on le parcourt du regard,
    /// on le montre à un contrôleur, on le photographie. Une bulle de
    /// conversation ne se prête à aucun des trois.
    private func reportCard(_ report: AssistantReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(report.title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if report.alertCount > 0 {
                    Text("\(report.alertCount) à voir")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange, in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if report.rows.isEmpty {
                Text("Rien à afficher.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            } else {
                ForEach(report.rows) { row in
                    if row.id != report.rows.first?.id {
                        Divider().padding(.leading, 14)
                    }
                    reportRow(row)
                }
            }

            if let note = report.note {
                Divider()
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private func reportRow(_ row: AssistantReport.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.label)
                    .font(.callout)
                Text(row.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(row.value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(row.isAlert ? Color.orange : Color.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - La photo

    /// L'appareil photo dans le fil, et non dans un écran à part.
    ///
    /// Le bon de livraison se photographie sur le quai, une main sur le
    /// carton. Sortir de la conversation pour revenir ensuite ferait perdre
    /// le fil, et le livreur n'attend pas.
    @ViewBuilder
    private var captureCard: some View {
        if let prompt = captureRequest {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "doc.viewfinder")
                        .font(.title3)
                        .foregroundStyle(Color.brand)
                        .frame(width: 28)

                    Text(prompt)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }

                #if canImport(UIKit)
                if CameraPicker.isAvailable {
                    Button {
                        isTyping = false
                        isPresentingCamera = true
                    } label: {
                        Label("Prendre la photo", systemImage: "camera.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("L'appareil photo n'est pas disponible ici. Ouvrez le registre des réceptions pour saisir le contrôle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                #endif

                Text("La lecture se fait sur l'iPhone. La photo ne quitte pas l'appareil.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
    }

    // MARK: - L'accord

    /// La carte n'apparaît qu'au moment de décider.
    ///
    /// Elle double la voix sans la remplacer : « oui » suffit quand les
    /// mains sont prises, le bouton reste là quand le bruit couvre tout.
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
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )

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
                    isConversing = false
                    dictation.stop()
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

                Text("Dites « oui » pour valider, « non » pour corriger.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )

        case .idle, .thinking, .awaitingDetail:
            EmptyView()
        }
    }

    // MARK: - Le micro

    private var microphone: some View {
        Button {
            if isConversing || dictation.isListening {
                isConversing = false
                dictation.stop()
                narrator.stop()
            } else {
                beginListening()
            }
        } label: {
            ZStack {
                // L'anneau suit la voix. Il ne décore pas : le voir rester
                // plat pendant qu'on parle, c'est comprendre aussitôt que
                // le micro est couvert.
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 104, height: 104)
                    .scaleEffect(reduceMotion ? 1 : 1 + dictation.level * 0.4)
                    .animation(.easeOut(duration: 0.12), value: dictation.level)

                Circle()
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    .frame(width: 104, height: 104)

                Circle()
                    .fill(circleFill)
                    .frame(width: 84, height: 84)

                Image(systemName: circleSymbol)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isConversing ? "Arrêter l'échange" : "Parler à l'assistant")
    }

    private var circleFill: some ShapeStyle {
        if dictation.isListening { return AnyShapeStyle(Color.red) }
        if narrator.isSpeaking { return AnyShapeStyle(Color.green) }
        return AnyShapeStyle(.white.opacity(0.22))
    }

    private var circleSymbol: String {
        if dictation.isListening { return "stop.fill" }
        if narrator.isSpeaking { return "speaker.wave.2.fill" }
        return "mic.fill"
    }

    // MARK: - Écrire plutôt que parler

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.cursor")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))

            TextField(
                "",
                text: $typed,
                prompt: Text(fieldPrompt).foregroundStyle(.white.opacity(0.6))
            )
            .textFieldStyle(.plain)
            .foregroundStyle(.white)
            .tint(.white)
            .submitLabel(.send)
            .focused($isTyping)
            .onSubmit { send(typed) }

            if !typed.isEmpty {
                Button {
                    send(typed)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Envoyer la demande")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.white.opacity(0.14), in: Capsule())
        .disabled(dictation.isListening)
        .opacity(dictation.isListening ? 0.5 : 1)
    }

    private var fieldPrompt: String {
        if dictation.isListening { return "Je vous écoute…" }
        if narrator.isSpeaking { return "Je parle…" }
        if hasStarted { return "Répondre ou demander autre chose" }
        return "Je voudrais… (ex : créer un produit)"
    }

    // MARK: - Trois départs possibles

    private var suggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.examples, id: \.self) { example in
                    Button {
                        send(example)
                    } label: {
                        Text(example)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private static let examples = [
        "Montre-moi les températures d'aujourd'hui",
        "J'entame un produit",
        "Relever une température"
    ]

    // MARK: - Ce qui ne marche pas

    /// Rien tant que tout va bien.
    ///
    /// Les trois voyants permanents répétaient la même bonne nouvelle sur
    /// la moitié de l'écran. Ils ne servent que le jour où quelque chose
    /// manque, et ce jour-là ils doivent nommer ce qui manque.
    @ViewBuilder
    private var trouble: some View {
        let problems = currentProblems
        if !problems.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(problems, id: \.self) { problem in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                        Text(problem)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var currentProblems: [String] {
        var problems: [String] = []
        if !dictation.supportsFrenchOnDevice {
            problems.append("Dictée française hors ligne indisponible sur cet iPhone.")
        }
        if !intelligence.isReady {
            problems.append(intelligence.advice ?? intelligence.summary)
        }
        if let reason = narrator.unavailableReason {
            problems.append(reason)
        }
        return problems
    }
}

#Preview {
    ZStack {
        Color.brand.ignoresSafeArea()
        ScrollView {
            AssistantPanel(operatorName: "Florijan")
                .padding(16)
        }
    }
}
