//
//  StoreStatusBanner.swift
//  HACCPPocket
//
//  Affichage de l'état du stockage local.
//
//  Une base de données mise de côté est l'incident le plus grave que puisse
//  connaître cette application : l'utilisateur croit tenir ses registres, et
//  il ne les a plus. Il ne doit donc pas l'apprendre en cherchant un ancien
//  relevé trois semaines plus tard, mais dès le premier lancement.
//

import SwiftUI

// MARK: - Passage par l'environnement

private struct StoreOutcomeKey: EnvironmentKey {
    static let defaultValue: AppSchema.StoreOutcome = .opened
}

extension EnvironmentValues {
    /// Comment le stockage s'est ouvert au lancement de l'application.
    var storeOutcome: AppSchema.StoreOutcome {
        get { self[StoreOutcomeKey.self] }
        set { self[StoreOutcomeKey.self] = newValue }
    }
}

// MARK: - Contenu du message

extension AppSchema.StoreOutcome {

    var isProblem: Bool { self != .opened }

    var title: String {
        switch self {
        case .opened:         "Stockage normal"
        case .recovered:      "Vos anciennes données n'ont pas pu être ouvertes"
        case .memoryFallback: "Rien n'est enregistré"
        }
    }

    var message: String {
        switch self {
        case .opened:
            "Les registres sont enregistrés normalement sur cet appareil."

        case .recovered(let fileName):
            "L'application est repartie sur un registre vierge. L'ancienne base n'a pas été supprimée : elle a été mise de côté sous le nom « \(fileName) ». Ne réinstallez pas l'application, contactez-nous pour tenter de la récupérer."

        case .memoryFallback:
            "L'appareil n'a pas autorisé la création du fichier de registre. Tout ce que vous saisirez maintenant sera perdu à la fermeture. Vérifiez l'espace de stockage disponible, puis redémarrez l'application."
        }
    }

    var systemImage: String {
        switch self {
        case .opened:         "internaldrive"
        case .recovered:      "exclamationmark.triangle.fill"
        case .memoryFallback: "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .opened:         .green
        case .recovered:      .orange
        case .memoryFallback: .red
        }
    }
}

// MARK: - Bandeau

/// Bandeau d'alerte affiché en tête d'accueil, uniquement quand quelque chose
/// s'est mal passé.
struct StoreStatusBanner: View {

    @Environment(\.storeOutcome) private var outcome

    var body: some View {
        if outcome.isProblem {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: outcome.systemImage)
                    .font(.title3)
                    .foregroundStyle(outcome.tint)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text(outcome.title)
                        .font(.subheadline.weight(.semibold))
                    Text(outcome.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                outcome.tint.opacity(0.10),
                in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                    .strokeBorder(outcome.tint.opacity(0.25), lineWidth: 1)
            }
        }
    }
}

// MARK: - Ligne de réglages

/// Version compacte pour la section « Mes données » des réglages. Toujours
/// affichée : quand tout va bien, elle rassure.
struct StoreStatusRow: View {

    @Environment(\.storeOutcome) private var outcome

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: outcome.systemImage)
                .foregroundStyle(outcome.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(outcome.title)
                    .font(.subheadline)
                Text(outcome.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}
