import AVFoundation
import XCTest
@testable import StemPlayerKit

/// Harnais de mesure du spike n°1.
///
/// Ce n'est pas une suite de tests de régression : c'est un instrument. Il
/// produit les chiffres à recopier dans `docs/adr/002-lecture-multipiste.md`,
/// et il doit tourner sur **iPhone physique** — un simulateur partage l'horloge
/// audio du Mac et rendrait la mesure de dérive sans valeur.
final class SpikeMeasurements: XCTestCase {

    /// Durée de la passe de lecture. `MELODIX_SPIKE_DURATION=180` pour la
    /// mesure longue, celle qui compte pour l'ADR.
    private var playbackDuration: TimeInterval {
        if let raw = ProcessInfo.processInfo.environment["MELODIX_SPIKE_DURATION"],
           let value = TimeInterval(raw) {
            return value
        }
        return 30
    }

    private static var stemURLs: [StemKind: URL]?

    /// Les pistes de test sont générées une fois pour toutes : à 44,1 kHz,
    /// écrire 4 × 3 minutes prend plusieurs secondes qu'il est inutile de payer
    /// à chaque test.
    private func sharedStems() throws -> [StemKind: URL] {
        if let existing = Self.stemURLs { return existing }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("melodix-spike-stems", isDirectory: true)

        // On génère un peu plus long que la passe de lecture, pour ne jamais
        // mesurer la dérive sur une piste déjà terminée.
        let duration = max(playbackDuration + 30, 60)
        let urls = try TestStems.generate(into: directory, duration: duration)

        Self.stemURLs = urls
        return urls
    }

    // MARK: - Mesures

    func testPlaybackInFileMode() throws {
        let report = try measurePlayback(source: .file)
        print(report.formatted)
        XCTAssertEqual(report.verdict, "PASSE", report.formatted)
    }

    /// Comparaison mémoire. On s'attend à ce que ce mode soit *coûteux* —
    /// l'objet de la mesure est de chiffrer de combien, pour trancher entre
    /// flux disque et décodage complet dans l'éditeur.
    func testPlaybackInBufferMode() throws {
        let report = try measurePlayback(source: .buffer)
        print(report.formatted)
        // Volontairement non bloquant : ce mode sert de point de comparaison,
        // pas de cible. Le seul verdict qui engage est celui du mode fichier.
        XCTAssertGreaterThan(report.memoryCostOfStemsMB, 0)
    }

    func testOfflineMixdownIsFasterThanRealtime() throws {
        let urls = try sharedStems()
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("melodix-spike-mixdown.wav")
        try? FileManager.default.removeItem(at: output)

        let result = try OfflineMixdown.render(
            urls: urls,
            settings: [.vocals: .init(gainDB: -3), .drums: .init(isMuted: true)],
            to: output
        )

        print(String(
            format: "Mixdown hors-ligne : %.1f s d'audio en %.2f s → %.1f× temps réel",
            result.audioSeconds, result.wallSeconds, result.realtimeFactor
        ))

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: output.path),
            "Le mixdown n'a produit aucun fichier"
        )
        XCTAssertGreaterThan(
            result.realtimeFactor, 5,
            "Le rendu sur l'appareil n'est pas assez rapide : l'ADR 000 suppose "
                + "un export local, cette mesure le remet en cause"
        )
    }

    // MARK: - Passe de mesure

    private func measurePlayback(source: StemSource) throws -> SpikeReport {
        let urls = try sharedStems()

        let player = StemPlayer()
        try player.configureAudioSession()

        let memoryBefore = Diagnostics.residentMemoryBytes()
        try player.load(urls: urls, source: source)
        let memoryAfter = Diagnostics.residentMemoryBytes()

        var peakMemory = memoryAfter
        var maxDriftFrames: Int64 = 0

        try player.play()
        // On laisse passer le lead-in : mesurer avant que les nœuds tournent
        // ne renverrait que des positions nulles.
        Thread.sleep(forTimeInterval: 1)

        let startedAt = Date()
        var toggledMute = false
        var toggledSolo = false

        while Date().timeIntervalSince(startedAt) < playbackDuration {
            Thread.sleep(forTimeInterval: 0.5)

            if let drift = player.driftFrames() {
                maxDriftFrames = max(maxDriftFrames, abs(drift))
            }
            peakMemory = max(peakMemory, Diagnostics.residentMemoryBytes())

            let elapsed = Date().timeIntervalSince(startedAt)

            // Les manipulations de mixage se font *pendant* la lecture :
            // c'est exactement le geste de l'éditeur, et le moment où une
            // implémentation naïve (stop/start par piste) se trahirait.
            if !toggledMute, elapsed > playbackDuration * 0.25 {
                player.setMuted(true, for: .drums)
                player.setGain(-6, for: .bass)
                toggledMute = true
            }
            if !toggledSolo, elapsed > playbackDuration * 0.5 {
                player.setMuted(false, for: .drums)
                player.setSoloed(true, for: .vocals)
                toggledSolo = true
            }
        }

        player.setSoloed(false, for: .vocals)

        // Le seek est le seul moment où la synchronisation est reconstruite :
        // on la remesure juste après.
        let midpoint = AVAudioFramePosition(player.sampleRate * 10)
        try player.seek(toFrame: midpoint)
        Thread.sleep(forTimeInterval: 1.5)
        let driftAfterSeek = player.driftFrames().map { abs($0) } ?? -1

        peakMemory = max(peakMemory, Diagnostics.residentMemoryBytes())
        player.stop()
        player.unload()

        return SpikeReport(
            source: source == .file ? "flux disque" : "décodé en mémoire",
            stemCount: urls.count,
            durationSeconds: playbackDuration,
            memoryBeforeLoadMB: Diagnostics.megabytes(memoryBefore),
            memoryAfterLoadMB: Diagnostics.megabytes(memoryAfter),
            peakMemoryMB: Diagnostics.megabytes(peakMemory),
            maxDriftFrames: maxDriftFrames,
            maxDriftMilliseconds: Double(maxDriftFrames) / player.sampleRate * 1_000,
            driftAfterSeekFrames: driftAfterSeek,
            mixdownRealtimeFactor: nil
        )
    }
}
