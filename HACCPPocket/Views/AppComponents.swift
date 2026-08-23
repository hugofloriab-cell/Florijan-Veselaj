//
//  AppComponents.swift
//  HACCPPocket
//
//  Petits composants et conventions visuelles partagés par tous les écrans.
//  Les couleurs sont dérivées des couleurs système : l'app reste lisible en
//  mode clair comme en mode sombre, sans palette à maintenir.
//

import SwiftUI

// MARK: - Couleurs métier

extension ExpiryUrgency {

    var color: Color {
        switch self {
        case .safe:     .green
        case .warning:  .yellow
        case .critical: .orange
        case .expired:  .red
        }
    }

    var systemImage: String {
        switch self {
        case .safe:     "checkmark.circle"
        case .warning:  "clock"
        case .critical: "exclamationmark.triangle"
        case .expired:  "xmark.octagon"
        }
    }
}

extension DashboardAlert.Severity {

    var color: Color {
        switch self {
        case .info:     .blue
        case .warning:  .orange
        case .critical: .red
        }
    }
}

extension ReadingMoment {

    var accentColor: Color {
        switch self {
        case .morning:  .orange
        case .evening:  .indigo
        case .delivery: .teal
        case .other:    .gray
        }
    }
}

// MARK: - Pastille

/// Étiquette arrondie et colorée, utilisée pour les statuts courts.
struct StatusBadge: View {

    let text: String
    let color: Color
    var systemImage: String?

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .labelStyle(.titleAndIcon)
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.16), in: Capsule())
        .foregroundStyle(color)
    }
}

// MARK: - Ligne d'alerte

struct AlertRow: View {

    let alert: DashboardAlert

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: alert.systemImage)
                .font(.title2)
                .foregroundStyle(alert.severity.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title)
                    .font(.subheadline.weight(.semibold))
                Text(alert.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Jauge d'avancement

/// Avancement de la routine du jour, avec son compteur.
struct ProgressRow: View {

    let title: String
    let completed: Int
    let total: Int

    private var progress: Double {
        total > 0 ? Double(completed) / Double(total) : 1
    }

    private var isComplete: Bool { completed >= total }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(completed) / \(total)")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isComplete ? Color.green : Color.orange)
            }
            ProgressView(value: progress)
                .tint(isComplete ? Color.green : Color.orange)
                .scaleEffect(x: 1, y: 1.4, anchor: .center)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Valeur de température

/// Affiche une température avec la couleur de son statut de conformité.
struct TemperatureLabel: View {

    let value: Double
    let isCompliant: Bool

    var body: some View {
        Text(AppFormatters.temperature(value))
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(isCompliant ? Color.primary : .red)
    }
}

// MARK: - Ligne d'information

/// Couple libellé / valeur, aligné comme dans les Réglages d'iOS.
struct InfoRow: View {

    let label: String
    let value: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                RowIcon(systemImage: systemImage, tint: .secondary, size: 26)
            }
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
