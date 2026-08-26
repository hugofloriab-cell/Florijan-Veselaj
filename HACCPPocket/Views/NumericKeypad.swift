//
//  NumericKeypad.swift
//  HACCPPocket
//
//  Pavé numérique de saisie des températures.
//
//  Pourquoi ne pas utiliser le clavier système : il occupe la moitié de
//  l'écran, ses touches font 20 points de haut, et en cuisine on saisit avec
//  des gants, une sonde dans l'autre main. Ce pavé n'a que ce qui sert —
//  chiffres, virgule, signe moins, effacement — avec des cibles deux fois
//  plus grandes et une virgule qui ne peut pas être saisie deux fois.
//

import SwiftUI

struct NumericKeypad: View {

    @Binding var text: String

    /// Le signe moins n'a de sens que pour une température.
    var allowsNegative: Bool = true

    /// Chiffres après la virgule. Un dixième de degré suffit largement.
    var maximumDecimals: Int = 1

    private let separator = ","

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(1...9, id: \.self) { digit in
                key("\(digit)") { append("\(digit)") }
            }

            if allowsNegative {
                key("−", isSecondary: true) { toggleSign() }
                    .accessibilityLabel("Changer le signe")
            } else {
                key(separator, isSecondary: true) { appendSeparator() }
            }

            key("0") { append("0") }

            if allowsNegative {
                key(separator, isSecondary: true) { appendSeparator() }
            } else {
                deleteKey
            }

            if allowsNegative {
                deleteKey
            }
        }
    }

    private var deleteKey: some View {
        key(systemImage: "delete.left", isSecondary: true) { deleteLast() }
            .accessibilityLabel("Effacer le dernier caractère")
    }

    // MARK: - Touches

    private func key(
        _ title: String? = nil,
        systemImage: String? = nil,
        isSecondary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title2.weight(.medium))
                } else if let title {
                    Text(title)
                        .font(.system(size: 26, weight: .medium, design: .rounded))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                isSecondary ? Color.secondary.opacity(0.14) : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .foregroundStyle(isSecondary ? Color.secondary : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Édition

    private func append(_ character: String) {
        // On borne le nombre de décimales plutôt que d'accepter « 3,4567 »,
        // qu'aucune sonde de cuisine ne sait produire.
        if let range = text.range(of: separator) {
            let decimals = text.distance(from: range.upperBound, to: text.endIndex)
            guard decimals < maximumDecimals else { return }
        }
        text.append(character)
    }

    private func appendSeparator() {
        guard !text.contains(separator) else { return }
        // « ,5 » n'est pas lisible : on complète en « 0,5 ».
        if text.isEmpty || text == "-" { text.append("0") }
        text.append(separator)
    }

    private func toggleSign() {
        if text.hasPrefix("-") {
            text.removeFirst()
        } else {
            text = "-" + text
        }
    }

    private func deleteLast() {
        guard !text.isEmpty else { return }
        text.removeLast()
    }
}

#Preview {
    NumericKeypad(text: .constant("3,5"))
        .padding()
}
