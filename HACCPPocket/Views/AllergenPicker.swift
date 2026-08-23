//
//  AllergenPicker.swift
//  HACCPPocket
//
//  Sélection des quatorze allergènes réglementaires.
//
//  Le libellé seul ne suffit pas : beaucoup de cuisiniers ignorent que
//  l'épeautre est du gluten, que le bouillon du commerce contient du céleri,
//  ou que la sauce Worcestershire contient du poisson. Chaque ligne porte donc
//  sa précision réglementaire — c'est elle qui évite l'oubli.
//

import SwiftUI

// MARK: - Écran de sélection

struct AllergenPickerView: View {

    @Binding var selection: Set<Allergen>

    /// Nom de ce qu'on est en train de renseigner, affiché en titre.
    var subject: String = ""

    var body: some View {
        List {
            Section {
                ForEach(Allergen.allCases) { allergen in
                    Button {
                        toggle(allergen)
                    } label: {
                        AllergenRow(
                            allergen: allergen,
                            isSelected: selection.contains(allergen)
                        )
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Allergènes présents")
            } footer: {
                Text("Liste fixée par l'annexe II du règlement européen 1169/2011. Elle est fermée : ces quatorze substances sont les seules dont la déclaration est obligatoire.")
            }

            if !selection.isEmpty {
                Section {
                    Button(role: .destructive) {
                        selection.removeAll()
                    } label: {
                        Label("Tout décocher", systemImage: "xmark.circle")
                    }
                }
            }
        }
        .navigationTitle(subject.isEmpty ? "Allergènes" : subject)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ allergen: Allergen) {
        if selection.contains(allergen) {
            selection.remove(allergen)
        } else {
            selection.insert(allergen)
        }
    }
}

// MARK: - Ligne

private struct AllergenRow: View {

    let allergen: Allergen
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.brand : Color.secondary.opacity(0.5))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(allergen.label)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                Text(allergen.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Ligne récapitulative

/// Ligne à poser dans un formulaire : elle résume la sélection et ouvre
/// l'écran complet. Quatorze cases à cocher noieraient un formulaire.
struct AllergenSummaryRow: View {

    @Binding var selection: Set<Allergen>
    var subject: String = ""

    var body: some View {
        NavigationLink {
            AllergenPickerView(selection: $selection, subject: subject)
        } label: {
            HStack(spacing: 12) {
                RowIcon(
                    systemImage: selection.isEmpty ? "exclamationmark.shield" : "checkmark.shield.fill",
                    tint: selection.isEmpty ? .secondary : .brand
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Allergènes")
                        .font(.subheadline.weight(.medium))
                    Text(Allergen.summary(of: selection))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if !selection.isEmpty {
                    Text("\(selection.count)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Pastilles

/// Affichage compact d'une liste d'allergènes, pour les lignes de liste.
struct AllergenBadges: View {

    let allergens: Set<Allergen>

    var body: some View {
        if allergens.isEmpty {
            Text("Aucun allergène déclaré")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text(Allergen.summary(of: allergens))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

#Preview {
    NavigationStack {
        AllergenPickerView(selection: .constant([.gluten, .milk]), subject: "Lasagnes")
    }
}
