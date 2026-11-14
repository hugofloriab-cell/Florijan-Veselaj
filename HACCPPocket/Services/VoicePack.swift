//
//  VoicePack.swift
//  HACCPPocket
//
//  Les phrases fixes de l'assistant, dites une fois pour toutes.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI UN PAQUET PLUTÔT QUE DU TEMPS RÉEL
//  ─────────────────────────────────────────────────────────────────────────
//
//  L'assistant répète les mêmes phrases toute la journée : « Quelle
//  température ? », « C'est dans la plage. J'enregistre ? », « Nouvelle
//  fiche produit ». Les faire synthétiser à chaque fois par un service en
//  ligne, c'est payer mille fois la même chose, attendre le réseau mille
//  fois, et devenir muet dès que la box sature.
//
//  Ces phrases sont donc enregistrées une bonne fois, hors de l'application,
//  avec une voix de qualité, et publiées à côté du code. L'application les
//  récupère et les garde. Après quoi elles sont gratuites, instantanées, et
//  ne dépendent plus de rien.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI FICHIER PAR FICHIER ET PAS UNE ARCHIVE
//  ─────────────────────────────────────────────────────────────────────────
//
//  iOS ne sait pas ouvrir un zip sans bibliothèque tierce. Plutôt que d'en
//  embarquer une pour un seul usage, chaque phrase est un fichier à part :
//  le manifeste dit lesquelles existent, et chacune est prise quand elle
//  sert — ou toutes d'un coup en arrière-plan, le paquet pesant quelques
//  mégaoctets.
//
//  Avantage inattendu : une phrase ajoutée au paquet n'oblige pas à
//  retélécharger les soixante-dix autres.
//

import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class VoicePack {

    // MARK: - Où se trouve le paquet

    /// L'adresse publique du paquet.
    ///
    /// Au moment de publier sur l'App Store, remplacer `claude/ios-swiftui-app-dev-5ahyqs`
    /// par l'empreinte exacte du commit : une branche bouge, un commit non.
    /// Une version figée garantit qu'une application déjà installée ne verra
    /// jamais ses phrases changer sous elle.
    static let baseURL = URL(
        string: "https://raw.githubusercontent.com/hugofloriab-cell/Florijan-Veselaj/claude/ios-swiftui-app-dev-5ahyqs/VoicePack/"
    )!

    // MARK: - Ce que dit le manifeste

    struct Manifest: Codable {
        let version: Int
        let voix: String?
        let phrases: [Phrase]
    }

    struct Phrase: Codable {
        let texte: String
        let fichier: String
    }

    // MARK: - État observable par les réglages

    private(set) var voiceName: String?
    private(set) var phraseCount = 0
    private(set) var storedCount = 0
    private(set) var isPrefetching = false

    /// Vrai dès qu'au moins une phrase est utilisable hors ligne.
    var isReady: Bool { storedCount > 0 }

    // MARK: - Mémoire interne

    /// Empreinte du texte → nom de fichier. Construite au chargement pour
    /// que la recherche d'une phrase soit immédiate, sans parcourir la liste.
    @ObservationIgnored private var index: [String: String] = [:]

    /// Les phrases cherchées en vain. Sans ce garde-fou, une phrase absente
    /// du paquet relancerait un téléchargement à chaque fois qu'elle est dite.
    @ObservationIgnored private var missing: Set<String> = []

    @ObservationIgnored private var loaded = false

    // MARK: - Emplacement sur l'appareil

    /// Dans « Application Support » et non dans « Caches » : iOS vide les
    /// caches sous pression de stockage, et le paquet se retéléchargerait
    /// au pire moment, en plein service, sans réseau.
    private static var folder: URL? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }

        let directory = support.appendingPathComponent("VoicePack", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        return directory
    }

    private static var manifestFile: URL? {
        folder?.appendingPathComponent("manifest.json")
    }

    // MARK: - Chargement

    /// Charge le manifeste gardé sur l'appareil, puis tente une mise à jour.
    ///
    /// L'ordre compte : on est utilisable avant même de savoir si le réseau
    /// répond. Un démarrage en chambre froide doit parler quand même.
    func prepare() async {
        guard !loaded else { return }
        loaded = true

        if let local = storedManifest() {
            apply(local)
        }
        await refresh()
    }

    /// Va chercher le manifeste publié et l'adopte s'il est plus récent.
    func refresh() async {
        guard let remote = await fetchManifest() else { return }
        guard remote.version > (storedManifest()?.version ?? 0) || index.isEmpty else { return }

        store(remote)
        apply(remote)
    }

    private func apply(_ manifest: Manifest) {
        voiceName = manifest.voix
        phraseCount = manifest.phrases.count
        index = Dictionary(
            manifest.phrases.map { (Self.fingerprint($0.texte), $0.fichier) },
            uniquingKeysWith: { first, _ in first }
        )
        missing.removeAll()
        recount()
    }

    private func recount() {
        guard let folder = Self.folder else { storedCount = 0; return }
        storedCount = index.values.reduce(into: 0) { total, name in
            if FileManager.default.fileExists(
                atPath: folder.appendingPathComponent(name).path
            ) { total += 1 }
        }
    }

    // MARK: - Trouver une phrase

    /// Le fichier audio de cette phrase, s'il existe dans le paquet.
    ///
    /// Rend `nil` sans attendre quand la phrase n'y est pas — c'est le cas
    /// de toutes celles qui contiennent un nom de produit ou une
    /// température, forcément uniques. L'appelant passe alors à la suite.
    func audioFile(for text: String) async -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let key = Self.fingerprint(trimmed)
        guard let name = index[key], let folder = Self.folder else { return nil }

        let file = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: file.path) { return file }

        // Pas encore descendue. On lui laisse trois secondes : au-delà, se
        // taire pour attendre coûte plus cher que dire la phrase avec la
        // voix embarquée.
        guard !missing.contains(key) else { return nil }
        guard let data = await download(name, timeout: 3) else {
            missing.insert(key)
            return nil
        }

        try? data.write(to: file, options: .atomic)
        recount()
        return file
    }

    // MARK: - Tout prendre d'avance

    /// Descend les phrases manquantes, une par une, en arrière-plan.
    ///
    /// Appelé au premier lancement et depuis les réglages. Le paquet pèse
    /// quelques mégaoctets : autant le prendre tant qu'il y a du réseau,
    /// plutôt que phrase par phrase pendant un service.
    func prefetchAll() async {
        guard !isPrefetching, let folder = Self.folder else { return }
        isPrefetching = true
        defer { isPrefetching = false }

        for name in index.values {
            let file = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path) { continue }

            guard let data = await download(name, timeout: 20) else { continue }
            try? data.write(to: file, options: .atomic)
            recount()
        }
        missing.removeAll()
    }

    /// Efface le paquet gardé sur l'appareil. Le manifeste reste : les
    /// phrases redescendront à la demande.
    func removeStored() {
        guard let folder = Self.folder else { return }
        for name in index.values {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
        missing.removeAll()
        recount()
    }

    /// Le poids du paquet sur l'appareil, pour l'écran des réglages.
    var storedSize: String {
        guard let folder = Self.folder else { return "0 Ko" }
        let total: Int = index.values.reduce(into: 0) { sum, name in
            let path = folder.appendingPathComponent(name).path
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            sum += (attributes?[.size] as? Int) ?? 0
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(total))
    }

    // MARK: - Réseau

    private func fetchManifest() async -> Manifest? {
        guard let data = await get(Self.baseURL.appendingPathComponent("manifest.json"),
                                   timeout: 10) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    private func download(_ name: String, timeout: TimeInterval) async -> Data? {
        await get(Self.baseURL.appendingPathComponent(name), timeout: timeout)
    }

    private func get(_ url: URL, timeout: TimeInterval) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              !data.isEmpty
        else { return nil }

        return data
    }

    // MARK: - Fichiers

    private func storedManifest() -> Manifest? {
        guard let file = Self.manifestFile,
              let data = try? Data(contentsOf: file)
        else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    private func store(_ manifest: Manifest) {
        guard let file = Self.manifestFile,
              let data = try? JSONEncoder().encode(manifest)
        else { return }
        try? data.write(to: file, options: .atomic)
    }

    // MARK: - Empreinte

    /// La même empreinte que celle calculée par `Tools/generer-voix.py` :
    /// SHA-256 du texte en UTF-8. C'est ce qui relie une phrase dite dans le
    /// code au fichier enregistré des mois plus tôt.
    private static func fingerprint(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
