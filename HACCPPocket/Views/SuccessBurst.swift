//
//  SuccessBurst.swift
//  HACCPPocket
//
//  L'animation qui récompense une tâche terminée.
//
//  Pointer un nettoyage ou saisir un relevé n'a rien de gratifiant : c'est
//  une corvée qu'on repousse, et un registre incomplet commence toujours par
//  là. Une seconde de satisfaction au bon moment ne change rien à la
//  réglementation, mais elle change beaucoup à l'envie de cocher la ligne
//  suivante.
//
//  Elle reste courte et ne bloque jamais : on peut continuer à travailler
//  pendant qu'elle se joue.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Une étoile

private struct BurstStar: Identifiable {
    let id = UUID()
    /// Direction de départ, en radians.
    let angle: Double
    /// Distance parcourue.
    let distance: CGFloat
    let size: CGFloat
    let tint: Color
    let delay: Double
}

// MARK: - L'animation

struct SuccessBurst: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Message affiché sous la coche, quand il y en a un.
    var message: String?

    @State private var isExpanded = false
    @State private var checkScale: CGFloat = 0.3
    @State private var haloScale: CGFloat = 0.6
    @State private var haloOpacity: Double = 0.55

    /// Douze étoiles réparties en couronne, avec assez d'irrégularité pour
    /// que ça ne ressemble pas à une horloge.
    private let stars: [BurstStar] = (0..<12).map { index in
        let base = Double(index) / 12 * 2 * .pi
        return BurstStar(
            angle: base + Double.random(in: -0.18...0.18),
            distance: CGFloat.random(in: 56...96),
            size: CGFloat.random(in: 7...14),
            tint: [Color.green, .mint, .yellow, .teal].randomElement() ?? .green,
            delay: Double.random(in: 0...0.09)
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                // L'onde qui s'ouvre derrière la coche.
                Circle()
                    .stroke(Color.green.opacity(haloOpacity), lineWidth: 3)
                    .frame(width: 92, height: 92)
                    .scaleEffect(haloScale)

                if !reduceMotion {
                    ForEach(stars) { star in
                        Image(systemName: "sparkle")
                            .font(.system(size: star.size, weight: .bold))
                            .foregroundStyle(star.tint)
                            .offset(
                                x: isExpanded ? cos(star.angle) * star.distance : 0,
                                y: isExpanded ? sin(star.angle) * star.distance : 0
                            )
                            .scaleEffect(isExpanded ? 0.4 : 0.9)
                            .opacity(isExpanded ? 0 : 1)
                            .animation(
                                .easeOut(duration: 0.85).delay(star.delay),
                                value: isExpanded
                            )
                    }
                }

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(.white, Color.green)
                    .scaleEffect(checkScale)
                    .shadow(color: .green.opacity(0.35), radius: 12, y: 4)
            }
            .frame(width: 180, height: 180)

            if let message {
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        // Rien ne doit intercepter le doigt : l'animation se superpose au
        // travail en cours, elle ne l'interrompt pas.
        .allowsHitTesting(false)
        .onAppear(perform: start)
    }

    private func start() {
        playHaptic()

        guard !reduceMotion else {
            checkScale = 1
            haloOpacity = 0
            return
        }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.52)) {
            checkScale = 1
        }
        withAnimation(.easeOut(duration: 0.7)) {
            haloScale = 1.9
            haloOpacity = 0
        }

        isExpanded = true
    }

    private func playHaptic() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #endif
    }
}

// MARK: - Modificateur

/// Joue l'animation à chaque fois que `trigger` change de valeur.
///
/// Le déclencheur est un identifiant plutôt qu'un booléen : deux tâches
/// pointées coup sur coup doivent produire deux animations, ce qu'un booléen
/// remis à `true` alors qu'il l'est déjà ne permettrait pas.
struct SuccessBurstModifier: ViewModifier {

    let trigger: UUID?
    let message: String?

    @State private var visible = false
    @State private var currentTrigger: UUID?

    func body(content: Content) -> some View {
        content
            .overlay {
                if visible {
                    SuccessBurst(message: message)
                        .transition(.opacity)
                        .id(currentTrigger)
                }
            }
            .onChange(of: trigger) { _, newValue in
                guard let newValue else { return }
                currentTrigger = newValue
                show()
            }
    }

    private func show() {
        withAnimation(.easeOut(duration: 0.18)) { visible = true }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_150))
            withAnimation(.easeIn(duration: 0.28)) { visible = false }
        }
    }
}

extension View {
    /// Félicite l'utilisateur quand `trigger` change.
    func successBurst(trigger: UUID?, message: String? = nil) -> some View {
        modifier(SuccessBurstModifier(trigger: trigger, message: message))
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        SuccessBurst(message: "Nettoyage enregistré")
    }
}
