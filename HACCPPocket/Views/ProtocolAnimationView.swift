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

    // MARK: - Minutage

    /// Durée visée pour l'ensemble, en secondes.
    private static let targetDuration: Double = 20

    private static let introDuration: Double = 2.2
    private static let outroDuration: Double = 2.2

    /// Temps accordé à chaque étape.
    ///
    /// Il découle de la durée visée et du nombre d'étapes, mais reste borné :
    /// en dessous de deux secondes on n'a pas le temps de lire, au-delà de
    /// quatre et demie on décroche. Un protocole de douze étapes durera donc
    /// un peu plus de vingt secondes, et c'est le bon compromis.
    private var stepDuration: Double {
        let count = Double(max(1, procedure.steps.count))
        let available = Self.targetDuration - Self.introDuration - Self.outroDuration
        return min(4.5, max(2.0, available / count))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    progressBar
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    Spacer(minLength: 0)

                    content
                        .padding(.horizontal, 28)
                        .frame(maxWidth: 520)

                    Spacer(minLength: 0)

                    controls
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
            .navigationTitle(procedure.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            // Un appui n'importe où met en pause : en cuisine on est
            // interrompu, et courir après un petit bouton les mains grasses
            // n'est pas une option.
            .contentShape(Rectangle())
            .onTapGesture { isPlaying.toggle() }
            .task(id: frameKey) { await advance() }
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

    private var transition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.92)),
                removal: .opacity
              )
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
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.brand)
    }

    // MARK: - Déroulement

    /// Clé qui relance l'attente : changer d'image ou reprendre la lecture
    /// doit repartir d'un compteur neuf.
    private var frameKey: String {
        "\(currentSegment)-\(isPlaying)"
    }

    private func advance() async {
        guard isPlaying, !hasFinished else { return }

        let duration: Double = {
            switch frame {
            case .intro: return Self.introDuration
            case .step:  return stepDuration
            case .outro: return Self.outroDuration
            }
        }()

        try? await Task.sleep(for: .seconds(duration))
        guard !Task.isCancelled, isPlaying else { return }

        withAnimation(.easeInOut(duration: 0.35)) {
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
        hasFinished = false
        withAnimation(.easeInOut(duration: 0.25)) { frame = .intro }
        isPlaying = true
    }
}

#Preview {
    ProtocolAnimationView(procedure: .rapidCooling)
}
