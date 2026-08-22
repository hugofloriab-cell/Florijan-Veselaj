//
//  AppFormatters.swift
//  HACCPPocket
//
//  Formatage centralisé. Tout passe par `formatted(_:)` de Foundation, donc les
//  séparateurs décimaux et l'ordre jour/mois suivent la langue de l'appareil.
//

import Foundation

enum AppFormatters {

    // MARK: - Températures

    /// Ex. « 3,5 °C »
    static func temperature(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) °C"
    }

    /// Ex. « 0,0 °C à 4,0 °C »
    static func range(_ range: ClosedRange<Double>) -> String {
        "\(temperature(range.lowerBound)) à \(temperature(range.upperBound))"
    }

    /// Écart signé par rapport à une plage. Ex. « +3,5 °C »
    static func deviation(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(value.formatted(.number.precision(.fractionLength(1)))) °C"
    }

    // MARK: - Dates

    /// Ex. « 22/08/2026 »
    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year())
    }

    /// Ex. « 08:30 »
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    /// Ex. « 22/08/2026 à 08:30 »
    static func dateAndTime(_ date: Date) -> String {
        "\(shortDate(date)) à \(time(date))"
    }

    /// Ex. « samedi 22 août »
    static func longDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    /// Ex. « août 2026 » — titre des exports mensuels.
    static func monthTitle(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
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
