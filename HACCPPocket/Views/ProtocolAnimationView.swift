//
//  ProtocolAnimationView.swift
//  HACCPPocket
//
//  Le mode opératoire en images, joué comme une petite vidéo.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI CE N'EST PAS UNE VIDÉO
//  ─────────────────────────────────────────────────────────────────────────
//
//  L'idée de départ était d'embarquer des fichiers vidéo. Ce qui est joué
//  ici en est l'équivalent visuel, mais dessiné par l'application au moment
//  où on le regarde. Quatre raisons de préférer ce dessin à un fichier :
//
//  • LE POIDS. Vingt secondes de vidéo lisible pèsent quelques mégaoctets.
//    Multipliées par dix-huit modes opératoires, l'application gagnerait
//    plusieurs dizaines de mégaoctets — que chaque restaurateur téléchargera
//    depuis la 4G de sa cuisine.
//
//  • LA NETTETÉ. Un dessin vectoriel est net sur un iPhone comme sur un
//    iPad 13 pouces. Une vidéo encodée pour l'un est floue sur l'autre.
//
//  • LE MODE SOMBRE. Une vidéo garde son fond blanc la nuit. Ce dessin suit
//    le thème du système.
//
//  • LE TEXTE. Corriger une formulation dans une vidéo suppose de la
//    réencoder et de republier l'application. Ici, le texte vient des mêmes
//    `OperationProtocol` que la liste à cocher : une correction est faite à
//    un seul endroit, et les deux écrans suivent.
//
//  ─────────────────────────────────────────────────────────────────────────
//  UN SEUL MOTEUR, DIX-HUIT ANIMATIONS
//  ─────────────────────────────────────────────────────────────────────────
//
//  Rien ici n'est écrit pour un mode opératoire en particulier. L'animation
//  se construit à partir des étapes déjà rédigées : ajouter un protocole
//  ajoute son animation, sans une ligne de plus.
//
//  ─────────────────────────────────────────────────────────────────────────
//  LE RYTHME SUIT LA VOIX
//  ─────────────────────────────────────────────────────────────────────────
//
//  La première version enchaînait les images sur un minuteur calculé pour
//  tenir vingt secondes. C'était trop rapide : on n'avait pas fini de lire
//  qu'on passait à la suite.
//
//  Une image reste maintenant affichée tant que sa phrase n'est pas
//  prononcée, plus une respiration. Une étape longue tient donc l'écran plus
//  longtemps qu'une étape brève, ce qui est exactement le comportement
//  attendu — et il n'y a plus de minuteur à régler.
//
//  Voix coupée, la durée se calcule sur la longueur du texte, à une vitesse
//  de lecture confortable. Le rythme reste le même, en silence.
//

import SwiftUI

struct ProtocolAnimationView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let procedure: OperationProtocol

    /// Ce qui est à l'écran à un instant donné.
    private enum Frame: Equatable {
        case intro
        case step(Int)
        case outro
    }

    @State private var frame: Frame = .intro
    @State private var isPlaying = true
    @State private var hasFinished = false
    @State private var narrator = SpeechNarrator()

    /// La voix est active par défaut, et le choix est retenu : quelqu'un qui
    /// la coupe une fois ne veut pas la retrouver au protocole suivant.
    @AppStorage("haccp.protocol.narration") private var narrationEnabled = true
    @AppStorage("haccp.protocol.voiceHintSeen") private var hasDismissedVoiceHint = false

    /// Feuille de choix de la voix.
    ///
    /// Accessible depuis l'écran lui-même, et non seulement depuis les
    /// réglages : c'est en entendant la voix qu'on décide d'en changer.
    @State private var showsVoiceSettings = false

    /// Résumé ou version détaillée.
    ///
    /// Les deux souhaits de départ — « une vingtaine de secondes » et « une
    /// voix qui explique chaque étape de façon claire et précise » — ne
    /// tiennent pas ensemble : lire les explications complètes d'un mode
    /// opératoire prend une à deux minutes. Plutôt que de trancher à la
    /// place de l'utilisateur, l'écran propose les deux.
    @AppStorage("haccp.protocol.detailedNarration") private var isDetailed = false

    // MARK: - Rythme

    /// Respiration entre deux images.
    ///
    /// Enchaîner à la fin exacte de la phrase donne une impression de
    /// précipitation, même quand la lecture était au bon rythme.
    private static let breath: Double = 0.7

    /// Durée d'une image quand la voix est coupée.
    ///
    /// Calculée sur la longueur du texte : environ quatorze caractères par
    /// seconde, ce qui correspond à une lecture silencieuse confortable en
    /// français. Bornée pour qu'une phrase courte reste lisible et qu'une
    /// longue ne bloque pas l'écran.
    private func silentDuration(for text: String) -> Double {
        let estimated = Double(text.count) / 14.0
        return min(11, max(3.5, estimated))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    progressBar
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    // Défilement plutôt que troncature : la version détaillée
                    // affiche maintenant le « pourquoi » en entier, et sur un
                    // petit écran cela dépasse. Un texte coupé serait le même
                    // défaut que la voix qui saute des passages.
                    ScrollView {
                        content
                            .padding(.horizontal, 28)
                            .padding(.vertical, 16)
                            .frame(maxWidth: 520)
                    }
                    .defaultScrollAnchor(.center)
                    .scrollBounceBehavior(.basedOnSize)

                    modePicker
                        .padding(.horizontal, 40)
                        .padding(.bottom, 12)

                    voiceHint

                    controls
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
            .navigationTitle(procedure.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        narrator.stop()
                        isPlaying = false
                        showsVoiceSettings = true
                    } label: {
                        Label("Voix", systemImage: "speaker.wave.2.circle")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .sheet(isPresented: $showsVoiceSettings) {
                VoiceSettingsView(narrator: narrator)
            }
            // Un appui n'importe où met en pause : en cuisine on est
            // interrompu, et courir après un petit bouton les mains grasses
            // n'est pas une option.
            .contentShape(Rectangle())
            .onTapGesture {
                isPlaying.toggle()
                if !isPlaying { narrator.stop() }
            }
            .task(id: frameKey) { await advance() }
            .onDisappear { narrator.stop() }
        }
    }

    // MARK: - Barre de progression

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<segmentCount, id: \.self) { index in
                Capsule()
                    .fill(index <= currentSegment ? Color.brand : Color.brand.opacity(0.18))
                    .frame(height: 4)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentSegment)
    }

    private var segmentCount: Int { procedure.steps.count + 2 }

    private var currentSegment: Int {
        switch frame {
        case .intro:            return 0
        case .step(let index):  return index + 1
        case .outro:            return segmentCount - 1
        }
    }

    // MARK: - Contenu

    @ViewBuilder
    private var content: some View {
        switch frame {
        case .intro:
            titleCard(
                systemImage: procedure.systemImage,
                title: procedure.title,
                subtitle: procedure.subtitle,
                showsLogo: true
            )
            .transition(transition)

        case .step(let index):
            stepCard(procedure.steps[index], number: index + 1)
                .transition(transition)

        case .outro:
            titleCard(
                systemImage: "checkmark.seal.fill",
                title: "C'est tout",
                subtitle: procedure.commonMistake.map { "À éviter : \($0)" }
                    ?? "Le mode opératoire détaillé reste consultable à côté.",
                showsLogo: true
            )
            .transition(transition)
        }
    }

    /// Écran d'ouverture et de fermeture : le logo, puis le titre.
    private func titleCard(
        systemImage: String,
        title: String,
        subtitle: String,
        showsLogo: Bool
    ) -> some View {
        VStack(spacing: 18) {
            if showsLogo {
                BrandLogo(size: 62)
            }

            Image(systemName: systemImage)
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Color.brand)
                .symbolRenderingMode(.hierarchical)

            Text(title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Une étape : le numéro, le pictogramme, le geste, la précision.
    private func stepCard(_ step: ProtocolStep, number: Int) -> some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.brand.opacity(0.12))
                    .frame(width: 132, height: 132)

                Image(systemName: stepSymbol(for: number))
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Color.brand)
                    .symbolRenderingMode(.hierarchical)
            }
            .overlay(alignment: .topTrailing) {
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.brand, in: Circle())
                    .offset(x: 6, y: -6)
            }

            Text(step.title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(step.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let note = step.note {
                Label(note.origin.badge, systemImage: note.origin.systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.brand)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.brand.opacity(0.12), in: Capsule())

                // En version détaillée, le « pourquoi » est écrit en entier,
                // parce qu'il est lu en entier. Une pastille seule laisserait
                // la voix dire quelque chose qui n'est nulle part à l'écran.
                if isDetailed {
                    VStack(spacing: 6) {
                        Text(note.title)
                            .font(.footnote.weight(.semibold))
                        Text(note.explanation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Le pictogramme de l'étape.
    ///
    /// `ProtocolStep` n'en porte pas — les étapes ont été écrites pour être
    /// lues, pas dessinées. Plutôt que d'ajouter dix-huit fois une icône à la
    /// main, on réutilise celui du mode opératoire et on le fait alterner
    /// avec une flèche de progression : le regard voit qu'on avance, ce qui
    /// est tout ce qu'on demande à un schéma.
    private func stepSymbol(for number: Int) -> String {
        number.isMultiple(of: 2) ? "arrow.down.circle" : procedure.systemImage
    }

    // MARK: - Ce qui est prononcé

    /// Le texte lu à voix haute, strictement ce qui est affiché.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// LA VOIX NE SAUTE PLUS RIEN
    /// ─────────────────────────────────────────────────────────────────────
    ///
    /// Première version : en mode Résumé, la voix ne lisait que le numéro et
    /// le titre de l'étape, alors que l'écran affichait aussi la consigne.
    /// Résultat entendu, et à juste titre reproché : « elle ne lit que étape
    /// un, étape deux, elle ne lit pas les textes ». Le commentaire au-dessus
    /// prétendait d'ailleurs l'inverse — il mentait.
    ///
    /// Règle désormais : **tout ce qui est écrit à l'écran est prononcé**.
    /// Ce qui distingue les deux modes, c'est la quantité affichée, jamais un
    /// écart entre l'œil et l'oreille. Quelqu'un qui a les mains occupées
    /// doit pouvoir suivre sans regarder.
    private var spokenText: String {
        switch frame {
        case .intro:
            return "\(procedure.title). \(procedure.subtitle)."

        case .step(let index):
            let step = procedure.steps[index]
            var spoken = "Étape \(index + 1). \(step.title). \(step.detail)"

            // Le « pourquoi » n'est affiché qu'en version détaillée : il n'est
            // donc lu que là, pour que l'écran et la voix restent d'accord.
            if isDetailed, let note = step.note {
                spoken += " \(note.title) \(note.explanation)"
            }
            return spoken

        case .outro:
            guard let mistake = procedure.commonMistake else {
                return "C'est tout. Le mode opératoire détaillé reste consultable à côté."
            }
            return "C'est tout. L'erreur à éviter : \(mistake)"
        }
    }

    private var transition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.92)),
                removal: .opacity
              )
    }

    /// Résumé ou version détaillée.
    private var modePicker: some View {
        Picker("Version", selection: $isDetailed) {
            Text("Résumé").tag(false)
            Text("Détaillé").tag(true)
        }
        .pickerStyle(.segmented)
        .onChange(of: isDetailed) { _, _ in
            // Changer de version en cours de phrase donnerait un mélange des
            // deux : on repart proprement de l'image courante.
            narrator.stop()
        }
    }

    /// Signale une fois qu'une voix plus naturelle est téléchargeable.
    ///
    /// L'application ne peut pas la télécharger elle-même : les voix sont un
    /// réglage du système. Elle peut seulement dire où aller — et se taire
    /// dès que c'est fait, ou dès que la personne a compris.
    ///
    /// L'indication ne donne pas la marche à suivre : elle renvoie à l'écran
    /// « Voix », où elle est écrite une seule fois. Deux textes qui disent la
    /// même chose finissent toujours par diverger.
    @ViewBuilder
    private var voiceHint: some View {
        if narrationEnabled && narrator.usesCompactVoice && !hasDismissedVoiceHint {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "waveform")
                    .foregroundStyle(Color.brand)

                Text("Voix « \(narrator.voiceName) », la version d'origine. Une voix bien plus naturelle se télécharge gratuitement : touchez « Voix » en haut de cet écran, la marche à suivre y est.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    hasDismissedVoiceHint = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Commandes

    private var controls: some View {
        HStack(spacing: 24) {
            Button {
                goBack()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .disabled(frame == .intro)

            Button {
                if hasFinished { restart() } else { isPlaying.toggle() }
            } label: {
                Image(systemName: hasFinished ? "arrow.counterclockwise" : (isPlaying ? "pause.fill" : "play.fill"))
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.brand, in: Circle())
            }

            Button {
                goForward()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .disabled(frame == .outro)

            Button {
                narrationEnabled.toggle()
                if !narrationEnabled { narrator.stop() }
            } label: {
                Image(systemName: narrationEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(narrationEnabled ? "Couper la voix" : "Activer la voix")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.brand)
    }

    // MARK: - Déroulement

    /// Clé qui relance le déroulé : changer d'image, reprendre la lecture ou
    /// basculer la voix doit repartir d'une attente neuve.
    private var frameKey: String {
        "\(currentSegment)-\(isPlaying)-\(narrationEnabled)-\(isDetailed)"
    }

    /// Fait durer l'image le temps qu'il faut, puis passe à la suivante.
    ///
    /// La voix dicte le rythme quand elle est active ; sinon c'est la
    /// longueur du texte. Dans les deux cas, l'attente est annulable : une
    /// mise en pause ou une fermeture d'écran coupe net.
    private func advance() async {
        guard isPlaying, !hasFinished else { return }

        if narrationEnabled {
            await narrator.speak(spokenText)
        } else {
            try? await Task.sleep(for: .seconds(silentDuration(for: spokenText)))
        }

        guard !Task.isCancelled, isPlaying else { return }

        try? await Task.sleep(for: .seconds(Self.breath))
        guard !Task.isCancelled, isPlaying else { return }

        withAnimation(.easeInOut(duration: 0.45)) {
            switch frame {
            case .intro:
                frame = procedure.steps.isEmpty ? .outro : .step(0)

            case .step(let index):
                frame = index + 1 < procedure.steps.count ? .step(index + 1) : .outro

            case .outro:
                hasFinished = true
                isPlaying = false
            }
        }
    }

    private func goForward() {
        narrator.stop()
        withAnimation(.easeInOut(duration: 0.25)) {
            switch frame {
            case .intro:
                frame = procedure.steps.isEmpty ? .outro : .step(0)
            case .step(let index):
                frame = index + 1 < procedure.steps.count ? .step(index + 1) : .outro
            case .outro:
                break
            }
        }
    }

    private func goBack() {
        narrator.stop()
        withAnimation(.easeInOut(duration: 0.25)) {
            switch frame {
            case .intro:
                break
            case .step(let index):
                frame = index == 0 ? .intro : .step(index - 1)
            case .outro:
                frame = procedure.steps.isEmpty ? .intro : .step(procedure.steps.count - 1)
            }
        }
        hasFinished = false
    }

    private func restart() {
        narrator.stop()
        hasFinished = false
        withAnimation(.easeInOut(duration: 0.25)) { frame = .intro }
        isPlaying = true
    }
}

#Preview {
    ProtocolAnimationView(procedure: .rapidCooling)
}
