//
//  RegulatoryNoteView.swift
//  HACCPPocket
//
//  La pastille ⓘ et son explication.
//
//  Une application qui se contente d'imposer un chiffre forme des gens qui
//  appliquent sans comprendre — et qui se trompent dès que la situation sort
//  du cadre. Deux lignes de « pourquoi » au bon endroit valent une journée de
//  formation.
//

import SwiftUI

// MARK: - Pastille

/// Bouton discret qui ouvre l'explication d'une valeur.
struct RegulatoryBadge: View {

    let note: RegulatoryNote

    @State private var showsNote = false

    var body: some View {
        Button {
            showsNote = true
        } label: {
            Image(systemName: "info.circle")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.brand)
                .accessibilityLabel("Pourquoi cette valeur ?")
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showsNote) {
            RegulatoryNoteSheet(note: note)
        }
    }
}

// MARK: - Feuille d'explication

struct RegulatoryNoteSheet: View {

    @Environment(\.dismiss) private var dismiss

    let note: RegulatoryNote

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {

                    originBadge

                    Text(note.explanation)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        if let source = note.origin.source {
                            Label(source, systemImage: "text.book.closed")
                                .font(.footnote.weight(.medium))
                        }

                        Text(note.origin.disclaimer)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
                .readableWidth()
            }
            .navigationTitle(note.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var originBadge: some View {
        Label(note.origin.badge, systemImage: note.origin.systemImage)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(badgeColor.opacity(0.15), in: Capsule())
            .foregroundStyle(badgeColor)
    }

    /// Le vert dit « c'est écrit quelque part », l'orange dit « c'est vous qui
    /// l'assumez ». La couleur porte l'information avant le texte.
    private var badgeColor: Color {
        switch note.origin {
        case .regulation: .green
        case .practice:   .orange
        }
    }
}

#Preview {
    RegulatoryNoteSheet(note: ColdChainStandard.preparedDishes.note)
}
