//
//  EstablishmentDirectory.swift
//  HACCPPocket
//
//  Gestion de plusieurs établissements.
//
//  ─────────────────────────────────────────────────────────────────────────
//  UNE BASE PAR ÉTABLISSEMENT, ET C'EST VOLONTAIRE
//  ─────────────────────────────────────────────────────────────────────────
//
//  L'autre solution aurait été de tout garder dans une seule base et de
//  filtrer chaque écran par établissement. Elle a un défaut rédhibitoire
//  ici : il suffit d'un filtre oublié dans une requête pour qu'un relevé du
//  restaurant A apparaisse dans le registre du restaurant B. Sur un document
//  qui sert de preuve en contrôle, ce genre de fuite ne se rattrape pas.
//
//  Chaque établissement possède donc son propre fichier de base. Les données
//  ne peuvent pas se mélanger, puisqu'elles ne se croisent jamais. Basculer
//  d'un établissement à l'autre revient à ouvrir un autre registre — ce qui
//  est exactement ce qu'on fait dans la réalité.
//
//  Conséquence assumée : la sauvegarde, les scellés et le registre mensuel
//  portent sur l'établissement ouvert, pas sur l'ensemble. C'est correct :
//  un contrôle vise un établissement.
//

import Foundation
import Observation

// MARK: - Référence d'établissement

/// L'entrée d'annuaire. Le nom détaillé, l'adresse et le SIRET vivent dans la
/// base de l'établissement lui-même : ici, seul ce qui sert à choisir.
struct SiteReference: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String

    /// Nom du fichier de base, figé à la création. Renommer l'établissement
    /// ne doit jamais déplacer ses données.
    var storeName: String

    init(id: UUID = UUID(), name: String, storeName: String? = nil) {
        self.id = id
        self.name = name
        self.storeName = storeName ?? "HACCPPocket-\(id.uuidString)"
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Établissement sans nom"
            : name
    }
}

// MARK: - Annuaire

@MainActor
@Observable
final class EstablishmentDirectory {

    static let shared = EstablishmentDirectory()

    private enum Key {
        static let sites = "haccp.sites.v1"
        static let activeSite = "haccp.sites.active"
    }

    /// Nom du fichier utilisé avant l'arrivée du multi-établissement. Le
    /// premier site le conserve : sans cela, tous les utilisateurs existants
    /// verraient leur registre disparaître à la mise à jour.
    static let legacyStoreName = "HACCPPocket"

    private let defaults: UserDefaults

    private(set) var sites: [SiteReference] {
        didSet { persist() }
    }

    private(set) var activeSiteID: UUID {
        didSet { defaults.set(activeSiteID.uuidString, forKey: Key.activeSite) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let stored: [SiteReference]
        if let data = defaults.data(forKey: Key.sites),
           let decoded = try? JSONDecoder().decode([SiteReference].self, from: data),
           !decoded.isEmpty {
            stored = decoded
        } else {
            // Première ouverture, ou mise à jour depuis une version sans
            // multi-établissement : on adopte la base existante telle quelle.
            stored = [
                SiteReference(
                    name: "Mon établissement",
                    storeName: EstablishmentDirectory.legacyStoreName
                )
            ]
        }
        self.sites = stored

        let savedID = defaults.string(forKey: Key.activeSite).flatMap(UUID.init(uuidString:))
        self.activeSiteID = stored.first(where: { $0.id == savedID })?.id ?? stored[0].id

        // La première écriture fige l'annuaire, y compris le cas hérité.
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(sites) else { return }
        defaults.set(data, forKey: Key.sites)
    }

    // MARK: - Lecture

    var activeSite: SiteReference {
        sites.first { $0.id == activeSiteID } ?? sites[0]
    }

    var hasMultipleSites: Bool { sites.count > 1 }

    // MARK: - Édition

    @discardableResult
    func addSite(named name: String) -> SiteReference {
        let site = SiteReference(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        sites.append(site)
        return site
    }

    func rename(_ site: SiteReference, to name: String) {
        guard let index = sites.firstIndex(where: { $0.id == site.id }) else { return }
        sites[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func select(_ site: SiteReference) {
        guard sites.contains(where: { $0.id == site.id }) else { return }
        activeSiteID = site.id
    }

    /// Retire un établissement de l'annuaire.
    ///
    /// Le fichier de base n'est pas supprimé : ces registres doivent être
    /// conservés plusieurs années, et un retrait de la liste ne vaut pas
    /// décision de destruction. Le fichier reste sur l'appareil, récupérable.
    func removeSite(_ site: SiteReference) {
        guard sites.count > 1 else { return }
        sites.removeAll { $0.id == site.id }

        if activeSiteID == site.id {
            activeSiteID = sites[0].id
        }
    }
}
