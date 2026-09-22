//  ProtocoleSonde.swift
//
//  Décodage des trames de la sonde HACCP.
//
//  Ce fichier est la transcription Swift de sondes/PROTOCOLE-BLE.md. Il doit
//  rester d'accord avec le firmware (sondes/firmware/) et avec la fiche web
//  (checklist-petit-dejeuner.html, bloc « Sondes ») : trois implémentations du
//  même protocole, toute modification se reporte aux trois.

import Foundation
import CoreBluetooth

enum Protocole {
    static let service   = CBUUID(string: "E9EA0001-6D2C-4F8B-9A35-0B7C1D4E5F60")
    static let etat      = CBUUID(string: "E9EA0002-6D2C-4F8B-9A35-0B7C1D4E5F60")
    static let historique = CBUUID(string: "E9EA0003-6D2C-4F8B-9A35-0B7C1D4E5F60")
    static let commande  = CBUUID(string: "E9EA0004-6D2C-4F8B-9A35-0B7C1D4E5F60")

    static let version: UInt8 = 1

    /// Valeur sentinelle écrite par la sonde quand la mesure a échoué.
    static let temperatureInvalide: Int16 = Int16.min
}

struct Drapeaux: OptionSet, Codable {
    let rawValue: UInt8
    static let horlogeReglee = Drapeaux(rawValue: 0x01)
    static let alerteT       = Drapeaux(rawValue: 0x02)
    static let pileFaible    = Drapeaux(rawValue: 0x04)
    static let tamponPlein   = Drapeaux(rawValue: 0x08)
    static let capteurHS     = Drapeaux(rawValue: 0x10)
    static let reveilManuel  = Drapeaux(rawValue: 0x20)
}

// MARK: - Lecture d'entiers en petit-boutiste

/// `Data` venant de CoreBluetooth peut avoir un `startIndex` non nul ; on
/// indexe donc toujours relativement à lui, jamais à zéro.
extension Data {
    func octet(_ i: Int) -> UInt8? {
        guard i >= 0, i < count else { return nil }
        return self[startIndex + i]
    }
    func u16(_ i: Int) -> UInt16? {
        guard let a = octet(i), let b = octet(i + 1) else { return nil }
        return UInt16(a) | (UInt16(b) << 8)
    }
    func i16(_ i: Int) -> Int16? { u16(i).map { Int16(bitPattern: $0) } }
    func u32(_ i: Int) -> UInt32? {
        guard let a = octet(i), let b = octet(i + 1),
              let c = octet(i + 2), let d = octet(i + 3) else { return nil }
        return UInt32(a) | (UInt32(b) << 8) | (UInt32(c) << 16) | (UInt32(d) << 24)
    }
}

// MARK: - Caractéristique « État »

struct EtatSonde {
    let version: UInt8
    let drapeaux: Drapeaux
    let millivolts: UInt16
    let pilePourcent: UInt8
    let intervalleMinutes: UInt8
    let derniereCenti: Int16
    let enAttente: UInt16
    /// Horloge propre de la sonde, en secondes depuis sa mise sous tension.
    let tics: UInt32
    let unixReference: UInt32
    let offsetCenti: Int16

    init?(_ d: Data) {
        guard d.count >= 20,
              let v = d.octet(0), let f = d.octet(1),
              let mv = d.u16(2), let pile = d.octet(4), let interv = d.octet(5),
              let der = d.i16(6), let att = d.u16(8), let t = d.u32(10),
              let uref = d.u32(14), let off = d.i16(18) else { return nil }
        version = v
        drapeaux = Drapeaux(rawValue: f)
        millivolts = mv
        pilePourcent = pile
        intervalleMinutes = interv
        derniereCenti = der
        enAttente = att
        tics = t
        unixReference = uref
        offsetCenti = off
    }
}

// MARK: - Caractéristique « Historique »

/// Un relevé tel que la sonde l'envoie : daté dans *son* horloge, pas la nôtre.
struct ReleveBrut {
    let tics: UInt32
    let centi: Int16
    let pilePourcent: UInt8
    let drapeaux: Drapeaux
}

struct PaquetHistorique {
    let premierIndex: UInt16
    let releves: [ReleveBrut]
    /// Paquet vide : la sonde a fini de déverser.
    var estFin: Bool { releves.isEmpty }

    init?(_ d: Data) {
        guard d.count >= 4, let idx = d.u16(0), let n = d.u16(2) else { return nil }
        premierIndex = idx
        var sortie: [ReleveBrut] = []
        sortie.reserveCapacity(Int(n))
        for k in 0..<Int(n) {
            let o = 4 + k * 8
            guard o + 8 <= d.count,
                  let t = d.u32(o), let c = d.i16(o + 4),
                  let p = d.octet(o + 6), let f = d.octet(o + 7) else { break }
            sortie.append(ReleveBrut(tics: t, centi: c, pilePourcent: p,
                                     drapeaux: Drapeaux(rawValue: f)))
        }
        releves = sortie
    }
}

// MARK: - Commandes

enum Commande {
    case reglerHorloge(Date)
    case deverser(depuis: UInt16)
    case acquitter(jusqua: UInt16)
    case intervalle(minutes: UInt8)
    case etalonnage(centi: Int16)
    case seuils(minCenti: Int16, maxCenti: Int16)
    case resterEveillee
    case nommer(String)

    var trame: Data {
        var d = Data()
        func u16(_ v: UInt16) { d.append(UInt8(v & 0xFF)); d.append(UInt8(v >> 8)) }
        func u32(_ v: UInt32) {
            d.append(UInt8(v & 0xFF));         d.append(UInt8((v >> 8) & 0xFF))
            d.append(UInt8((v >> 16) & 0xFF)); d.append(UInt8((v >> 24) & 0xFF))
        }
        switch self {
        case .reglerHorloge(let date):
            d.append(0x01); u32(UInt32(max(0, date.timeIntervalSince1970)))
        case .deverser(let depuis):
            d.append(0x02); u16(depuis)
        case .acquitter(let jusqua):
            d.append(0x03); u16(jusqua)
        case .intervalle(let m):
            d.append(0x04); d.append(m)
        case .etalonnage(let c):
            d.append(0x05); u16(UInt16(bitPattern: c))
        case .seuils(let mn, let mx):
            d.append(0x06); u16(UInt16(bitPattern: mn)); u16(UInt16(bitPattern: mx))
        case .resterEveillee:
            d.append(0x07)
        case .nommer(let nom):
            d.append(0x08)
            d.append(contentsOf: Array(nom.utf8.prefix(16)))
        }
        return d
    }
}
