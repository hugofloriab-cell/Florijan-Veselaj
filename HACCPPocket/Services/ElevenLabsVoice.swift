//
//  ElevenLabsVoice.swift
//  HACCPPocket
//
//  Une voix de synthèse en ligne, et le cache qui la rend tenable.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUE ÇA COÛTE, ET POURQUOI LE CACHE N'EST PAS UN LUXE
//  ─────────────────────────────────────────────────────────────────────────
//
//  ElevenLabs facture au caractère. L'assistant dit quatre-vingts phrases
//  fixes — « Quelle température ? », « C'est oui ou non ? », « C'est
//  enregistré. » — qui représentent 4 300 caractères en tout. Sans cache,
//  une cuisine ordinaire en consomme trois à vingt fois le quota mensuel
//  gratuit, en répétant toujours les mêmes mots.
//
//  Avec le cache, chaque phrase distincte coûte une fois, pour toujours.
//  Les répétitions deviennent gratuites ET instantanées, ce qui compte
//  autant : un aller-retour réseau prend entre trois dixièmes et une
//  seconde, un fichier déjà sur le disque prend zéro.
//
//  ─────────────────────────────────────────────────────────────────────────
//  LE CACHE SURVIT AUX PURGES
//  ─────────────────────────────────────────────────────────────────────────
//
//  Rangé dans Application Support et non dans Caches : iOS vide le second
//  quand la place manque, et chaque purge se paierait en caractères. Ce
//  dossier-là n'est pas du cache jetable, c'est un achat.
//

import CryptoKit
import Foundation

enum ElevenLabsVoice {

    // MARK: - Les voix proposées

    struct Choice: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let note: String
    }

    /// Aucune voix du catalogue n'est « française » à proprement parler :
    /// les modèles multilingues parlent toutes les langues, avec plus ou
    /// moins d'accent. Celles-ci ont été écoutées en français.
    static let voices: [Choice] = [
        Choice(id: "cjVigY5qzO86Huf0OWal", name: "Eric", note: "Homme, posé, timbre chaud"),
        Choice(id: "Xb7hH8MSUJpSbSDYk0k2", name: "Alice", note: "Femme, claire, articulée"),
        Choice(id: "JBFqnCBsd6RMkjVDRZzb", name: "George", note: "Homme, grave, narratif"),
        Choice(id: "EXAVITQu4vr4xnSDxMaL", name: "Sarah", note: "Femme, douce, rassurante"),
        Choice(id: "SAz9YHcvj6GT2YYXdXww", name: "River", note: "Neutre, informatif")
    ]

    static let defaultVoiceID = "cjVigY5qzO86Huf0OWal"

    /// Deux modèles, deux compromis.
    enum Quality: String, CaseIterable, Identifiable, Sendable {
        /// Le plus naturel, autour de huit dixièmes de seconde.
        case natural = "eleven_multilingual_v2"
        /// Deux fois plus rapide, un peu moins nuancé.
        case fast = "eleven_flash_v2_5"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .natural: "Plus naturelle"
            case .fast:    "Plus rapide"
            }
        }

        var note: String {
            switch self {
            case .natural: "Meilleur rendu, environ 0,8 seconde d'attente."
            case .fast:    "Environ 0,35 seconde. Préférable en plein service."
            }
        }
    }

    // MARK: - Les échecs, dits en clair

    enum Failure: LocalizedError, Equatable {
        case noKey
        case rejected
        case quotaExhausted
        case offline
        case server(Int)

        var errorDescription: String? {
            switch self {
            case .noKey:          "Aucune clé ElevenLabs enregistrée."
            case .rejected:       "Clé ElevenLabs refusée. Vérifiez-la dans les réglages."
            case .quotaExhausted: "Quota ElevenLabs épuisé pour ce mois."
            case .offline:        "Pas de réseau : voix embarquée utilisée."
            case .server(let code): "ElevenLabs a répondu \(code)."
            }
        }
    }

    // MARK: - Synthèse

    static func synthesize(
        _ text: String,
        voiceID: String,
        quality: Quality,
        key: String
    ) async throws -> Data {

        guard var components = URLComponents(
            string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)"
        ) else { throw Failure.server(0) }

        // Le format le plus léger qui reste propre sur un haut-parleur de
        // téléphone : inutile de télécharger du 128 kbps pour une phrase
        // de six mots dans une cuisine.
        components.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_64")]

        guard let url = components.url else { throw Failure.server(0) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Au-delà, l'attente ne vaut plus le coup : la voix embarquée
        // répondra plus vite que le réseau.
        request.timeoutInterval = 8

        let body: [String: Any] = [
            "text": text,
            "model_id": quality.rawValue,
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.offline
        }

        guard let http = response as? HTTPURLResponse else { throw Failure.server(0) }

        switch http.statusCode {
        case 200:
            guard !data.isEmpty else { throw Failure.server(200) }
            return data
        case 401, 403:
            throw Failure.rejected
        case 429:
            throw Failure.quotaExhausted
        default:
            throw Failure.server(http.statusCode)
        }
    }
}

// MARK: - Le cache

/// Les phrases déjà payées, gardées sur l'appareil.
enum VoiceCache {

    /// Le fichier correspondant à cette phrase, s'il existe déjà.
    static func existing(for text: String, voiceID: String, quality: String) -> URL? {
        let url = location(for: text, voiceID: voiceID, quality: quality)
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Range un son synthétisé et rend son emplacement.
    @discardableResult
    static func store(_ data: Data, for text: String, voiceID: String, quality: String) -> URL? {
        guard let url = location(for: text, voiceID: voiceID, quality: quality) else { return nil }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Le nom du fichier mêle la phrase, la voix et le modèle.
    ///
    /// Changer de voix ne doit pas rendre l'ancien son : il serait juste,
    /// et dit par quelqu'un d'autre.
    private static func location(for text: String, voiceID: String, quality: String) -> URL? {
        guard let folder else { return nil }
        let seed = "\(voiceID)|\(quality)|\(text)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent("\(name).mp3")
    }

    static var folder: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("VoiceCache", isDirectory: true)
    }

    /// Ce que le cache occupe, et combien de phrases il contient.
    static var summary: (count: Int, bytes: Int) {
        guard let folder,
              let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.fileSizeKey])
        else { return (0, 0) }

        let bytes = files.reduce(0) { total, file in
            total + ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return (files.count, bytes)
    }

    static func empty() {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}
