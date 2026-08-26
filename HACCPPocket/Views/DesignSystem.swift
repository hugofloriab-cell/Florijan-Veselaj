//
//  DesignSystem.swift
//  HACCPPocket
//
//  Constantes et composants partagés par tous les écrans.
//
//  L'app s'utilise debout, en cuisine, souvent à bout de bras et parfois avec
//  les mains occupées : les cibles sont larges, les chiffres gros, et la
//  couleur ne sert qu'à signaler un état, jamais à décorer.
//

import SwiftUI

// MARK: - Mesures

enum DS {
    /// Rayon des surfaces : tuiles un peu plus arrondies que les cartes.
    static let cardRadius: CGFloat = 16
    static let tileRadius: CGFloat = 20
    static let iconRadius: CGFloat = 9

    static let tileHeight: CGFloat = 118
    static let rowIconSize: CGFloat = 32

    static let gutter: CGFloat = 12
    static let sectionSpacing: CGFloat = 22

    /// Largeur maximale d'une colonne de texte. Au-delà, l'œil perd la ligne
    /// en revenant à la marge gauche : c'est ce qui rend illisible un écran
    /// d'iPhone étiré sur toute la largeur d'un iPad.
    static let readableWidth: CGFloat = 780
}

// MARK: - Couleurs des registres

extension AppRouter.Destination {

    /// Une couleur par destination : sur une grille de raccourcis, c'est la
    /// couleur qu'on reconnaît avant de lire le libellé.
    var tint: Color {
        switch self {
        case .today:        .brand
        case .temperatures: .blue
        case .products:     .orange
        case .cleaning:     .green
        case .registers:    .indigo
        case .menu:         .pink
        case .history:      .teal
        case .report:       .purple
        case .settings:     .gray
        }
    }
}

// MARK: - Pavé de raccourci

/// Tuile compacte, plus petite que `MetricTile` : elle ne porte pas de
/// chiffre, seulement une destination.
struct ShortcutTile: View {

    let title: String
    let systemImage: String
    var tint: Color = .brand
    /// Pastille de rappel, quand quelque chose attend à l'arrivée.
    var badgeCount: Int = 0

    var body: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if badgeCount > 0 {
                    Text("\(min(badgeCount, 99))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                        .offset(x: 7, y: -5)
                }
            }

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .frame(height: 92)
        .frame(maxWidth: .infinity)
        .cardSurface()
        .contentShape(Rectangle())
    }
}

// MARK: - Largeur de lecture

extension View {
    /// Borne le contenu à une largeur lisible et le centre. Sans effet sur un
    /// iPhone, dont l'écran est déjà plus étroit que la borne.
    func readableWidth(_ maxWidth: CGFloat = DS.readableWidth) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Surface

/// Fond de carte, adapté au thème clair comme au thème sombre.
struct CardSurface: ViewModifier {
    var radius: CGFloat = DS.cardRadius

    func body(content: Content) -> some View {
        content
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
    }
}

extension View {
    func cardSurface(radius: CGFloat = DS.cardRadius) -> some View {
        modifier(CardSurface(radius: radius))
    }
}

// MARK: - Icône de ligne

/// Pastille d'icône uniforme, utilisée dans toutes les listes. C'est elle qui
/// donne à l'ensemble son air de famille.
struct RowIcon: View {

    let systemImage: String
    var tint: Color = .brand
    var size: CGFloat = DS.rowIconSize

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                tint.opacity(0.15),
                in: RoundedRectangle(cornerRadius: DS.iconRadius, style: .continuous)
            )
    }
}

// MARK: - Tuile de synthèse

/// Tuile carrée du tableau de bord : un chiffre, ce qu'il désigne, et le cas
/// échéant l'avancement. Conçue pour être lue d'un coup d'œil.
struct MetricTile: View {

    let title: String
    let value: String
    var caption: String?
    var systemImage: String
    var tint: Color = .brand
    /// Avancement de 0 à 1. `nil` masque la barre.
    var progress: Double?
    /// Met la tuile en évidence quand une action est attendue.
    var needsAttention: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                RowIcon(systemImage: systemImage, tint: tint)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(needsAttention ? tint : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let progress {
                ProgressView(value: progress)
                    .tint(tint)
                    .padding(.top, 6)
            } else if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: DS.tileHeight, alignment: .leading)
        .cardSurface(radius: DS.tileRadius)
        .overlay {
            RoundedRectangle(cornerRadius: DS.tileRadius, style: .continuous)
                .strokeBorder(needsAttention ? tint.opacity(0.45) : Color.clear, lineWidth: 1.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: DS.tileRadius, style: .continuous))
    }
}

// MARK: - Carte d'alerte

struct AlertCard: View {

    let alert: DashboardAlert

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: alert.systemImage)
                .font(.title3)
                .foregroundStyle(alert.severity.color)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title)
                    .font(.subheadline.weight(.semibold))
                Text(alert.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            alert.severity.color.opacity(0.10),
            in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                .strokeBorder(alert.severity.color.opacity(0.25), lineWidth: 1)
        }
    }
}

// MARK: - Titre de section

/// Intitulé de section hors des `List`, aligné sur la typographie d'iOS.
struct SectionTitle: View {

    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.headline)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.medium))
            }
        }
    }
}

// MARK: - Ligne d'action compacte

/// Ligne de raccourci utilisée hors des `List` : icône, libellé, chevron.
struct ActionRow: View {

    let title: String
    var subtitle: String?
    var systemImage: String
    var tint: Color = .brand
    var trailingText: String?

    var body: some View {
        HStack(spacing: 12) {
            RowIcon(systemImage: systemImage, tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if let trailingText {
                Text(trailingText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .cardSurface()
        .contentShape(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
    }
}
