//
//  AssistantPanel.swift
//  HACCPPocket
//
//  L'assistant en haut de l'accueil, et tout le reste en dessous.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI CE BLOC NE RESSEMBLE À RIEN D'AUTRE DANS L'APPLICATION
//  ─────────────────────────────────────────────────────────────────────────
//
//  Le reste de l'application est une suite de listes grises : c'est un
//  registre, et un registre doit être sobre et lisible. L'assistant, lui,
//  est l'endroit où l'on parle. S'il avait la même apparence, il passerait
//  pour une rubrique parmi douze.
//
//  D'où le fond coloré, le texte blanc et la taille : on doit le trouver
//  sans chercher, les mains occupées, en entrant en cuisine.
//
//  ─────────────────────────────────────────────────────────────────────────
//  DEUX FAÇONS DE DEMANDER
//  ─────────────────────────────────────────────────────────────────────────
//
//  La voix d'abord, parce que c'est le but : parler au lieu de taper. Mais
//  une hotte à pleine puissance couvre une voix, et il y a des services où
//  la dictée ne passera pas. Le champ de saisie est là pour ces moments,
//  pas comme un pis-aller : une demande tapée suit exactement le même
//  chemin qu'une demande dite.
//

import SwiftUI

struct AssistantPanel: View {

    /// Le prénom saisi dans les réglages, s'il y en a un.
    var operatorName: String = ""

    /// Dessine son propre fond coloré.
    ///
    /// Faux quand la page entière est déjà bleue : un cadre dans un fond de
    /// même couleur ne délimiterait rien et ferait une tache.
    var drawsBackground: Bool = true

    /// Lance l'assistant. Chaîne vide pour la voix, sinon la demande déjà
    /// écrite — l'assistant la traitera comme si elle avait été dite.
    var onStart: (String) -> Void

    @State private var typed = ""
    @FocusState private var isTyping: Bool

    var body: some View {
        VStack(spacing: 18) {
            greeting
            microphone
            field
            suggestions
        }
        .padding(.vertical, drawsBackground ? 24 : 8)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background {
            if drawsBackground {
                background.clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    // MARK: - Les morceaux

    private var background: some View {
        LinearGradient(
            colors: [Color.brand, Color.brand.opacity(0.78)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

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
    }

    private var microphone: some View {
        Button {
            isTyping = false
            onStart("")
        } label: {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 104, height: 104)

                Circle()
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    .frame(width: 104, height: 104)

                Image(systemName: "mic.fill")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Parler à l'assistant")

    }

    /// Le champ de saisie, pour les services où la voix ne passe pas.
    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.cursor")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))

            TextField(
                "",
                text: $typed,
                prompt: Text("Je voudrais… (ex : créer un produit)")
                    .foregroundStyle(.white.opacity(0.6))
            )
            .textFieldStyle(.plain)
            .foregroundStyle(.white)
            .tint(.white)
            .submitLabel(.send)
            .focused($isTyping)
            .onSubmit(send)

            if !typed.isEmpty {
                Button(action: send) {
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
    }

    /// Trois départs possibles, pour qui ne sait pas quoi dire.
    ///
    /// Elles partent directement : une suggestion qu'il faudrait ensuite
    /// valider d'un second geste ne ferait gagner aucun temps.
    private var suggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.examples, id: \.self) { example in
                    Button {
                        isTyping = false
                        onStart(example)
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
        "J'entame un produit",
        "Relever une température",
        "J'ai fini un nettoyage"
    ]

    private func send() {
        let request = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        typed = ""
        isTyping = false
        onStart(request)
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        AssistantPanel(operatorName: "Florijan") { _ in }
            .padding(16)
    }
}
