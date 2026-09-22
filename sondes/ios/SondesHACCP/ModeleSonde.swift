//  ModeleSonde.swift
//
//  Les données d'une sonde et leur conservation sur l'appareil.
//  Aucun serveur : tout reste dans le bac à sable de l'application, comme la
//  fiche web garde tout dans le stockage local de la tablette.

import Foundation

// MARK: - Types d'enceinte

enum TypeEnceinte: String, Codable, CaseIterable, Identifiable {
    case positif, negatif

    var id: String { rawValue }

    /// Normes inscrites sur la fiche papier, en centièmes de degré.
    var bornes: (min: Int16, max: Int16) {
        switch self {
        case .positif: return (100, 400)      // +1 à +4 °C
        case .negatif: return (-2300, -1800)  // -23 à -18 °C
        }
    }

    var libelle: String {
        switch self {
        case .positif: return "Positif +1 à +4 °C"
        case .negatif: return "Négatif -23 à -18 °C"
        }
    }
}

// MARK: - Un relevé daté

struct Releve: Codable, Identifiable, Hashable {
    let date: Date
    /// Température en centièmes de degré : entier, comme sur la sonde.
    let centi: Int16
    let pilePourcent: UInt8

    var id: Date { date }
    var celsius: Double { Double(centi) / 100 }
}

// MARK: - Une sonde

struct Sonde: Codable, Identifiable {
    /// Identifiant CoreBluetooth du périphérique, stable pour cette application.
    let id: UUID
    var nom: String
    var type: TypeEnceinte = .positif
    var releves: [Releve] = []

    // Dernier état connu
    var derniereCenti: Int16?
    var pilePourcent: UInt8?
    var millivolts: UInt16?
    var intervalleMinutes: UInt8?
    var offsetCenti: Int16 = 0
    var drapeauxBruts: UInt8 = 0
    var derniereSynchro: Date?
    var derniereErreur: String?
    var etalonneeLe: Date?

    /// Repères du recalage d'horloge : tics et heure réelle de la dernière
    /// synchronisation réussie.
    var referenceTics: UInt32?
    var referenceDate: Date?

    var drapeaux: Drapeaux { Drapeaux(rawValue: drapeauxBruts) }
    var bornes: (min: Int16, max: Int16) { type.bornes }

    /// Au-delà de 36 h sans relevé, la sonde est considérée muette.
    var estMuette: Bool {
        guard let s = derniereSynchro else { return true }
        return Date().timeIntervalSince(s) > 36 * 3600
    }

    func horsSeuils(_ centi: Int16?) -> Bool {
        guard let c = centi, c != Protocole.temperatureInvalide else { return false }
        return c < bornes.min || c > bornes.max
    }
}

// MARK: - Recalage de l'horloge

/// Sans quartz, l'oscillateur de la sonde dérive de quelques pour cent — jusqu'à
/// une demi-heure par jour. Elle horodate donc dans ses propres secondes, et
/// c'est le téléphone qui rétablit l'heure réelle, par interpolation entre deux
/// synchronisations. Voir le § 6 de PROTOCOLE-BLE.md.
struct Dateur {
    private let ticsActuels: UInt32
    private let maintenant: Date
    private let reference: (tics: UInt32, date: Date)?

    init(sonde: Sonde, ticsActuels: UInt32, maintenant: Date) {
        self.ticsActuels = ticsActuels
        self.maintenant = maintenant
        if let t0 = sonde.referenceTics, let r0 = sonde.referenceDate,
           ticsActuels > t0 &+ 3600, maintenant > r0 {
            let pente = maintenant.timeIntervalSince(r0) / Double(ticsActuels - t0)
            // Une pente aberrante trahit un redémarrage de la sonde ou une
            // horloge de téléphone modifiée : on retombe sur la cadence nominale.
            reference = (0.8...1.25).contains(pente) ? (t0, r0) : nil
        } else {
            reference = nil
        }
    }

    func date(pourTics tics: UInt32) -> Date {
        if let r = reference {
            let pente = maintenant.timeIntervalSince(r.date) / Double(ticsActuels - r.tics)
            return r.date.addingTimeInterval(Double(Int64(tics) - Int64(r.tics)) * pente)
        }
        return maintenant.addingTimeInterval(-Double(Int64(ticsActuels) - Int64(tics)))
    }
}

// MARK: - Bilans

extension Sonde {
    /// Fusionne de nouveaux relevés sans créer de doublon, et plafonne
    /// l'historique à deux mois — au-delà, c'est l'export qui prend le relais.
    mutating func ranger(_ nouveaux: [Releve], plafond: Int = 3000) {
        var vus = Set(releves.map { Int($0.date.timeIntervalSince1970 / 60) })
        for r in nouveaux {
            let cle = Int(r.date.timeIntervalSince1970 / 60)
            if vus.insert(cle).inserted { releves.append(r) }
        }
        releves.sort { $0.date < $1.date }
        if releves.count > plafond { releves.removeFirst(releves.count - plafond) }
    }

    /// Autonomie restante, déduite de la pente de décharge réellement observée.
    /// Une pile lithium a un palier très plat : il faut deux bonnes semaines de
    /// recul avant que l'estimation veuille dire quelque chose.
    var joursRestants: Int? {
        guard let fin = releves.last else { return nil }
        let limite = fin.date.addingTimeInterval(-60 * 86400)
        guard let debut = releves.first(where: { $0.date >= limite }) else { return nil }
        let jours = fin.date.timeIntervalSince(debut.date) / 86400
        let perte = Double(debut.pilePourcent) - Double(fin.pilePourcent)
        guard jours >= 14, perte >= 2 else { return nil }
        return max(0, Int(Double(fin.pilePourcent) / (perte / jours)))
    }

    struct BilanJour {
        let nombre: Int
        let minCenti: Int16
        let maxCenti: Int16
        let moyenneCenti: Int16
        /// Nombre d'épisodes d'au moins deux relevés consécutifs hors normes.
        let ecarts: Int
    }

    /// Un écart n'est retenu qu'au bout de deux relevés consécutifs hors normes,
    /// soit une heure : une porte ouverte ou un dégivrage ne compte pas.
    func bilan(du jour: Date, calendrier: Calendar = .current) -> BilanJour? {
        let debut = calendrier.startOfDay(for: jour)
        guard let fin = calendrier.date(byAdding: .day, value: 1, to: debut) else { return nil }
        let duJour = releves.filter {
            $0.date >= debut && $0.date < fin && $0.centi != Protocole.temperatureInvalide
        }
        guard !duJour.isEmpty else { return nil }

        var mini = duJour[0].centi, maxi = duJour[0].centi
        var somme = 0, suite = 0, ecarts = 0
        for r in duJour {
            mini = min(mini, r.centi)
            maxi = max(maxi, r.centi)
            somme += Int(r.centi)
            if horsSeuils(r.centi) {
                suite += 1
                if suite == 2 { ecarts += 1 }
            } else {
                suite = 0
            }
        }
        return BilanJour(nombre: duJour.count, minCenti: mini, maxCenti: maxi,
                         moyenneCenti: Int16(somme / duJour.count), ecarts: ecarts)
    }
}

// MARK: - Mise en forme

enum Format {
    static func degres(_ centi: Int16?) -> String {
        guard let c = centi, c != Protocole.temperatureInvalide else { return "—" }
        let v = Double(c) / 100
        let signe = v > 0 ? "+" : (v < 0 ? "-" : "")
        return signe + String(format: "%.1f", abs(v)).replacingOccurrences(of: ".", with: ",") + " °C"
    }

    static func duree(jours: Int) -> String {
        if jours < 45 { return "\(jours) jours" }
        let mois = Int((Double(jours) / 30.4).rounded())
        if mois < 24 { return "\(mois) mois" }
        let ans = (Double(jours) / 365).rounded(toPlaces: 1)
        return String(format: "%.1f", ans).replacingOccurrences(of: ".", with: ",") + " ans"
    }
}

private extension Double {
    func rounded(toPlaces n: Int) -> Double {
        let f = pow(10.0, Double(n))
        return (self * f).rounded() / f
    }
}

// MARK: - Conservation

/// Un fichier JSON dans le conteneur de l'application. Simple, inspectable,
/// et exportable tel quel vers la direction.
actor Depot {
    private let url: URL

    init(nomFichier: String = "sondes.json") {
        let dossier = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        url = dossier.appendingPathComponent(nomFichier)
    }

    func charger() -> [Sonde] {
        guard let d = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Sonde].self, from: d)) ?? []
    }

    func enregistrer(_ sondes: [Sonde]) {
        guard let d = try? JSONEncoder().encode(sondes) else { return }
        // Écriture atomique : une interruption ne laisse pas un fichier tronqué.
        try? d.write(to: url, options: .atomic)
    }
}
