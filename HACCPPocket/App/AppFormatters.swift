//
//  AppFormatters.swift
//  HACCPPocket
//
//  Formatage centralisé. Tout passe par `formatted(_:)` de Foundation, donc les
//  séparateurs décimaux et l'ordre jour/mois suivent la langue de l'appareil.
//

import Foundation

enum AppFormatters {

    /// L'application est rédigée en français et vise la restauration française.
    /// On fixe donc la locale des formats plutôt que de suivre celle de
    /// l'appareil : un iPhone réglé en anglais afficherait sinon « 22 Aug 2026 »
    /// au milieu d'une interface française.
    static let locale = Locale(identifier: "fr_FR")

    // MARK: - Températures

    /// Ex. « 3,5 °C »
    static func temperature(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)).locale(locale))) °C"
    }

    /// Ex. « 0,0 °C à 4,0 °C »
    static func range(_ range: ClosedRange<Double>) -> String {
        "\(temperature(range.lowerBound)) à \(temperature(range.upperBound))"
    }

    /// Écart signé par rapport à une plage. Ex. « +3,5 °C »
    static func deviation(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(value.formatted(.number.precision(.fractionLength(1)).locale(locale))) °C"
    }

    // MARK: - Dates

    /// Ex. « 22/08/2026 »
    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(locale))
    }

    /// Ex. « 22/08 »
    ///
    /// Sans l'année, pour les étiquettes : trois centimètres de large ne
    /// laissent pas la place de quatre chiffres qui n'apprennent rien sur un
    /// produit dont la durée de vie se compte en jours.
    static func dayAndMonth(_ date: Date) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(locale))
    }

    /// Ex. « 08:30 »
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(locale))
    }

    /// Ex. « 22/08/2026 à 08:30 »
    static func dateAndTime(_ date: Date) -> String {
        "\(shortDate(date)) à \(time(date))"
    }

    /// Ex. « samedi 22 août »
    static func longDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }

    /// Met une majuscule à la première lettre seulement. `capitalized`
    /// capitaliserait chaque mot et donnerait « Samedi 22 Août ».
    static func sentenceCased(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased(with: locale) + text.dropFirst()
    }

    /// Ex. « 2026-08-23 » — horodatage neutre pour les noms de fichiers.
    /// Volontairement indépendant de la locale : un nom de fichier doit rester
    /// triable et lisible sur n'importe quel ordinateur.
    static func fileStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Ex. « 2026-08-24-0217 » — horodatage à la minute, pour nommer un
    /// fichier sans jamais écraser celui de la veille ni celui d'il y a
    /// une heure.
    static func fileTimestamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d-%02d-%02d-%02d%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0
        )
    }

    /// Ex. « août 2026 » — titre des exports mensuels.
    static func monthTitle(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year().locale(locale))
    }

    /// « Aujourd'hui », « Hier », sinon la date courte.
    static func relativeDay(_ date: Date, reference: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: reference) { return "Aujourd'hui" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: reference),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Hier"
        }
        return shortDate(date)
    }

    // MARK: - Saisie numérique

    /// Convertit une saisie clavier en `Double`. Accepte la virgule française,
    /// le signe moins typographique et les espaces insécables du pavé numérique.
    static func parseTemperature(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "\u{2212}", with: "-")   // signe moins Unicode
            .replacingOccurrences(of: "\u{00A0}", with: "")     // espace insécable
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "°", with: "")
            .replacingOccurrences(of: "C", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty, cleaned != "-" else { return nil }
        return Double(cleaned)
    }
}
