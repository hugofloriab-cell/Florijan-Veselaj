//
//  AssistantReport.swift
//  HACCPPocket
//
//  Ce que l'assistant montre, par opposition à ce qu'il dit.
//
//  ─────────────────────────────────────────────────────────────────────────
//  LA QUATRIÈME SORTIE
//  ─────────────────────────────────────────────────────────────────────────
//
//  L'assistant savait faire trois choses : poser une question, proposer une
//  action, l'exécuter. Il lui manquait la plus utile au quotidien : montrer.
//
//  « Les températures d'aujourd'hui » n'a pas de réponse parlée acceptable.
//  Égrener six relevés à voix haute est illisible, et surtout invérifiable :
//  on ne peut pas relire une phrase. Un tableau se parcourt, se montre à un
//  contrôleur, et se photographie.
//
//  La voix garde ce qu'elle fait bien : la conclusion. « Deux relevés hors
//  plage, vérifiez la chambre froide. » Le détail est à l'écran.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE TYPE NE CONNAÎT NI SWIFTDATA NI L'INTERFACE
//  ─────────────────────────────────────────────────────────────────────────
//
//  Il ne contient que du texte déjà mis en forme. C'est voulu : il traverse
//  la conversation, est conservé dans le fil, et pourra demain venir d'une
//  sonde connectée plutôt que d'une saisie manuelle sans que rien change
//  ici. Le registre du mois et le récapitulatif de la journée emprunteront
//  la même structure.
//

import Foundation

struct AssistantReport: Identifiable, Equatable, Sendable {

    struct Row: Identifiable, Equatable, Sendable {
        let id = UUID()

        /// Ce dont on parle : « Frigo cuisine ».
        let label: String

        /// La précision secondaire : « Matin · 11 h 20 ».
        let detail: String

        /// Ce qu'on lit en bout de ligne : « 3,5 °C ».
        let value: String

        /// Signalé en orange, et compté dans la conclusion.
        let isAlert: Bool
    }

    let id = UUID()
    let title: String
    let rows: [Row]

    /// La conclusion, dite à voix haute. Jamais le détail.
    let spoken: String

    /// Ce qu'il faut faire, affiché sous le tableau. Un relevé hors plage
    /// appelle une action corrective : le taire serait un faux service.
    let note: String?

    var alertCount: Int { rows.filter(\.isAlert).count }
}

// MARK: - Construction à partir du registre

enum AssistantReportBuilder {

    /// Le relevé des températures d'une journée.
    ///
    /// Une enceinte sans relevé apparaît quand même, signalée : un tableau
    /// qui ne montrerait que ce qui a été fait laisserait croire que tout
    /// est fait. C'est précisément l'oubli qu'un contrôle sanctionne.
    @MainActor
    static func temperatures(
        for equipment: [Equipment],
        on day: Date = .now,
        calendar: Calendar = .current
    ) -> AssistantReport {

        let active = equipment.filter(\.isActive)
        let title = calendar.isDateInToday(day)
            ? "Températures du jour"
            : "Températures du \(Self.dayFormatter.string(from: day))"

        guard !active.isEmpty else {
            return AssistantReport(
                title: title,
                rows: [],
                spoken: "Aucune enceinte n'est enregistrée. Ajoutez-en une dans l'écran Températures.",
                note: nil
            )
        }

        var rows: [AssistantReport.Row] = []
        var outOfRange: [String] = []
        var missing: [String] = []

        for item in active {
            let readings = item.readings(on: day, calendar: calendar)

            guard !readings.isEmpty else {
                missing.append(item.name)
                rows.append(AssistantReport.Row(
                    label: item.name,
                    detail: "Aucun relevé",
                    value: "—",
                    isAlert: true
                ))
                continue
            }

            for reading in readings {
                if !reading.isCompliant, !outOfRange.contains(item.name) {
                    outOfRange.append(item.name)
                }
                rows.append(AssistantReport.Row(
                    label: item.name,
                    detail: "\(reading.moment.label) · \(Self.timeFormatter.string(from: reading.recordedAt))",
                    value: reading.formattedValue,
                    isAlert: !reading.isCompliant
                ))
            }
        }

        return AssistantReport(
            title: title,
            rows: rows,
            spoken: spokenConclusion(outOfRange: outOfRange, missing: missing, total: rows.count),
            note: note(outOfRange: outOfRange, missing: missing)
        )
    }

    // MARK: - Ce qui se dit, et ce qui s'écrit

    /// La conclusion parlée. L'écart passe avant le reste.
    ///
    /// Un relevé hors plage peut vouloir dire une rupture de chaîne du
    /// froid, donc des aliments à écarter. C'est la seule chose qui ne
    /// supporte pas d'attendre la fin de la phrase.
    private static func spokenConclusion(
        outOfRange: [String],
        missing: [String],
        total: Int
    ) -> String {
        if !outOfRange.isEmpty {
            let names = enumerate(outOfRange)
            return outOfRange.count == 1
                ? "Attention, \(names) est sorti de sa plage. Vérifiez les aliments."
                : "Attention, \(names) sont sortis de leur plage. Vérifiez les aliments."
        }

        if !missing.isEmpty {
            let names = enumerate(missing)
            return missing.count == 1
                ? "Tout est conforme, mais il manque le relevé de \(names)."
                : "Tout est conforme, mais il manque les relevés de \(names)."
        }

        return total == 0
            ? "Aucun relevé aujourd'hui."
            : "Tout est conforme aujourd'hui."
    }

    private static func note(outOfRange: [String], missing: [String]) -> String? {
        if !outOfRange.isEmpty {
            return "Un relevé hors plage appelle une action corrective écrite. "
                + "Ouvrez le relevé concerné pour la renseigner."
        }
        if !missing.isEmpty {
            return "Les enceintes sans relevé sont signalées : un registre incomplet "
                + "se remarque autant qu'un écart."
        }
        return nil
    }

    /// « le frigo, la chambre froide et le congélateur ».
    private static func enumerate(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        let head = names.dropLast().joined(separator: ", ")
        return "\(head) et \(names[names.count - 1])"
    }

    // MARK: - Mise en forme

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH'h'mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMMM"
        return formatter
    }()
}
