//
//  OperatorField.swift
//  HACCPPocket
//
//  Champ « Opérateur » commun à tous les formulaires de traçabilité.
//
//  Un registre sanitaire n'a de valeur que s'il nomme la personne qui a fait
//  le geste. Retaper ce nom vingt fois par jour au clavier, sur un plan de
//  travail, avec des gants : personne ne le fera. D'où ce champ qui propose
//  l'équipe déjà connue en un seul appui.
//

import SwiftUI

struct OperatorField: View {

    @Environment(UserPreferences.self) private var preferences

    @Binding var name: String

    /// Intitulé affiché dans le champ vide.
    var placeholder: String = "Opérateur"

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .onSubmit { preferences.rememberOperator(name) }

            if !preferences.operatorSuggestions.isEmpty {
                Menu {
                    ForEach(preferences.operatorSuggestions, id: \.self) { suggestion in
                        Button {
                            name = suggestion
                        } label: {
                            if suggestion.caseInsensitiveCompare(name) == .orderedSame {
                                Label(suggestion, systemImage: "checkmark")
                            } else {
                                Text(suggestion)
                            }
                        }
                    }

                    if !trimmedName.isEmpty && !isKnown {
                        Divider()
                        Button {
                            preferences.rememberOperator(name)
                        } label: {
                            Label("Ajouter « \(trimmedName) » à l'équipe", systemImage: "person.badge.plus")
                        }
                    }
                } label: {
                    Image(systemName: "person.2")
                        .font(.body)
                        .foregroundStyle(.brand)
                        .accessibilityLabel("Choisir dans l'équipe")
                }
                .buttonStyle(.plain)
            }
        }
        // Le nom saisi à la main rejoint l'équipe dès qu'on quitte l'écran :
        // la liste se remplit à l'usage, sans annuaire à tenir à jour.
        .onDisappear { preferences.rememberOperator(name) }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isKnown: Bool {
        preferences.knownOperators.contains {
            $0.caseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }
}

#Preview {
    Form {
        OperatorField(name: .constant("Marc"))
    }
    .environment(UserPreferences.shared)
}
