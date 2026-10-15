//
//  AssistantEquipment.swift
//  HACCPPocket
//
//  Faire correspondre une enceinte dite à une enceinte réelle.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI L'ASSISTANT DOIT CONNAÎTRE LES VRAIES ENCEINTES
//  ─────────────────────────────────────────────────────────────────────────
//
//  Un assistant qui invente « Frigo 1 » parce que ça sonne plausible écrit
//  un relevé rattaché à rien. La liste réelle lui est donc donnée, et le
//  rapprochement entre ce qui est dit et ce qui existe est fait ici, par du
//  code : le modèle propose un nom, ce fichier décide s'il correspond.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUI SE DIT EN CUISINE
//  ─────────────────────────────────────────────────────────────────────────
//
//  Personne ne dit « enceinte positive ». On dit le frigo, le congél, la
//  chambre. Les synonymes du métier sont donc rattachés au type de
//  l'appareil, pour que « le congél » trouve un matériel enregistré sous le
//  nom « Armoire négative ».
//
//  En cas d'égalité entre deux enceintes, on ne tranche pas : l'assistant
//  demande laquelle. Se tromper d'enceinte fausse deux registres à la fois,
//  celui qui reçoit le relevé et celui qui ne le reçoit pas.
//

import Foundation

/// Une enceinte, réduite à ce dont l'assistant a besoin.
///
/// Volontairement sans lien vers SwiftData : ce type traverse des frontières
/// de concurrence, et un objet `@Model` ne le peut pas.
struct EquipmentBrief: Identifiable, Equatable, Sendable {

    let name: String
    let typeLabel: String
    let location: String
    let minTemperature: Double
    let maxTemperature: Double

    /// Le nom sert de clé : c'est lui qu'on prononce, et c'est par lui que
    /// l'écran d'accueil retrouvera le matériel au moment d'écrire.
    var id: String { name }

    func accepts(_ celsius: Double) -> Bool {
        celsius >= minTemperature && celsius <= maxTemperature
    }

    /// « entre 0 et 4 degrés », pour être dit à voix haute.
    var spokenRange: String {
        "entre \(Self.spoken(minTemperature)) et \(Self.spoken(maxTemperature)) degrés"
    }

    private static func spoken(_ value: Double) -> String {
        let rounded = value.rounded()
        let text = value == rounded
            ? String(Int(rounded))
            : String(format: "%.1f", value).replacingOccurrences(of: ".", with: " virgule ")
        return value < 0 ? "moins \(text.replacingOccurrences(of: "-", with: ""))" : text
    }
}

// MARK: - Le rapprochement

enum EquipmentMatcher {

    /// Trouve l'enceinte désignée, ou rien si le doute subsiste.
    ///
    /// - Returns: l'enceinte quand une seule sort du lot. En cas d'égalité
    ///   ou d'absence de mot commun, `nil` — et l'assistant demandera.
    static func match(_ spoken: String, in equipment: [EquipmentBrief]) -> EquipmentBrief? {
        let said = meaningfulWords(in: spoken)
        guard !said.isEmpty, !equipment.isEmpty else { return nil }

        var best: (brief: EquipmentBrief, score: Int)?
        var tied = false

        for brief in equipment {
            let score = said.intersection(vocabulary(of: brief)).count
            guard score > 0 else { continue }

            if let current = best {
                if score > current.score {
                    best = (brief, score)
                    tied = false
                } else if score == current.score {
                    tied = true
                }
            } else {
                best = (brief, score)
            }
        }

        guard let best, !tied else { return nil }
        return best.brief
    }

    /// Tous les mots par lesquels on peut désigner une enceinte.
    private static func vocabulary(of brief: EquipmentBrief) -> Set<String> {
        var words = meaningfulWords(in: brief.name)
        words.formUnion(meaningfulWords(in: brief.typeLabel))
        words.formUnion(meaningfulWords(in: brief.location))

        // Le vocabulaire de cuisine, rattaché au type.
        for (canonical, family) in synonyms where !words.isDisjoint(with: family) {
            words.formUnion(family)
            words.insert(canonical)
        }

        return words
    }

    /// Les familles de mots qui désignent la même chose.
    ///
    /// Elles jouent dans les deux sens : un matériel nommé « Armoire
    /// positive » devient trouvable par « frigo », et un matériel nommé
    /// « Frigo cuisine » reste trouvable par « enceinte positive ».
    private static let synonyms: [String: Set<String>] = [
        "froidpositif": ["frigo", "frigos", "frigidaire", "refrigerateur",
                         "refrigerateurs", "enceinte", "positive", "positif",
                         "armoire", "refrigere", "refrigeree"],
        "froidnegatif": ["congelateur", "congelateurs", "congel", "congelo",
                         "negative", "negatif", "surgeles", "surgele"],
        "chambre":      ["chambre", "froide", "cellier"],
        "vitrine":      ["vitrine", "vitrines", "presentoir", "buffet"],
        "cellule":      ["cellule", "refroidissement", "surgelation"],
        "chaud":        ["bain", "marie", "etuve", "chaud", "maintien", "chauffant"]
    ]

    /// Les mots porteurs de sens, sans les outils de la langue.
    ///
    /// Les mots d'un ou deux caractères partent aussi : « la », « du »,
    /// « le » n'identifient rien, et les garder ferait correspondre
    /// n'importe quelle enceinte à n'importe quelle phrase.
    private static func meaningfulWords(in text: String) -> Set<String> {
        let folded = text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "fr_FR")
        )
        let pieces = folded.split { !$0.isLetter && !$0.isNumber }
        return Set(
            pieces
                .map(String.init)
                .filter { $0.count > 2 && !stopWords.contains($0) }
        )
    }

    private static let stopWords: Set<String> = [
        "les", "des", "une", "est", "son", "sur", "dans", "pour", "avec",
        "temperature", "temperatures", "degre", "degres", "celsius",
        "releve", "releves", "relever", "enregistre", "enregistrer",
        "assistant", "voudrais", "veux", "fait", "faire", "mettre",
        "actuellement", "maintenant", "aujourd", "hui", "moins", "plus"
    ]
}
