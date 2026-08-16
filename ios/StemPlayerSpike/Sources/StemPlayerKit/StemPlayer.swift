import AVFoundation
import Darwin

/// Les quatre pistes produites par Demucs.
public enum StemKind: String, CaseIterable, Sendable {
    case vocals, drums, bass, other
}

/// Comment l'audio parvient au moteur.
///
/// Le choix n'est pas cosmétique : un morceau stéréo de 3 minutes en Float32
/// pèse environ 63 Mo une fois décodé. Quatre pistes en `.buffer`, c'est
/// ~250 Mo de mémoire résidente — de quoi se faire tuer par le système sur un
/// iPhone d'entrée de gamme. C'est précisément ce que ce spike doit mesurer.
public enum StemSource: Sendable {
    /// Lecture en flux depuis le disque. Défaut.
    case file
    /// Fichier entièrement décodé en mémoire.
    case buffer
}

public struct StemPlayerError: Error, CustomStringConvertible {
    public let description: String
    init(_ description: String) { self.description = description }
}

/// Lecteur multipiste : un `AVAudioPlayerNode` par stem, tous sur le même
/// moteur donc sur la même horloge de rendu.
///
/// Graphe par piste :  player → AVAudioUnitEQ (gain en dB) → mainMixerNode
///
/// L'étage EQ n'égalise rien : c'est un étage de gain. `AVAudioPlayerNode.volume`
/// est borné à 0…1 et ne sait donc pas monter au-dessus de l'unité, alors que le
/// schéma autorise jusqu'à +12 dB. `globalGain` couvre -96…+24 dB.
/// Le mute reste sur `player.volume` : c'est un interrupteur, pas un niveau, et
/// les garder séparés évite qu'un mute écrase le gain réglé par l'utilisateur.
public final class StemPlayer {

    private let engine = AVAudioEngine()
    private var players: [StemKind: AVAudioPlayerNode] = [:]
    private var gainStages: [StemKind: AVAudioUnitEQ] = [:]
    private var files: [StemKind: AVAudioFile] = [:]
    private var buffers: [StemKind: AVAudioPCMBuffer] = [:]

    private var gainsDB: [StemKind: Float] = [:]
    private var mutedKinds: Set<StemKind> = []
    private var soloedKinds: Set<StemKind> = []

    public private(set) var loadedKinds: [StemKind] = []
    public private(set) var sampleRate: Double = 44_100
    public private(set) var totalFrames: AVAudioFramePosition = 0

    /// Position de lecture demandée au dernier `play`/`seek`, en frames.
    private var startFrame: AVAudioFramePosition = 0

    public init() {}

    // MARK: - Session audio

    /// À appeler une fois avant toute lecture sur iOS.
    public func configureAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        #endif
    }

    // MARK: - Chargement

    /// - Parameter urls: une URL par piste. Toutes doivent partager le même
    ///   format : un écart de fréquence d'échantillonnage entre pistes est une
    ///   source de désynchronisation silencieuse, on le rejette explicitement.
    public func load(urls: [StemKind: URL], source: StemSource = .file) throws {
        guard !urls.isEmpty else { throw StemPlayerError("Aucune piste à charger") }

        unload()

        var canonicalFormat: AVAudioFormat?

        for kind in StemKind.allCases {
            guard let url = urls[kind] else { continue }

            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat

            if let canonical = canonicalFormat {
                guard format.sampleRate == canonical.sampleRate,
                      format.channelCount == canonical.channelCount else {
                    throw StemPlayerError(
                        "Format hétérogène sur \(kind.rawValue) : "
                            + "\(format.sampleRate) Hz / \(format.channelCount) canaux "
                            + "contre \(canonical.sampleRate) Hz / \(canonical.channelCount)"
                    )
                }
            } else {
                canonicalFormat = format
                sampleRate = format.sampleRate
            }

            totalFrames = max(totalFrames, file.length)

            let player = AVAudioPlayerNode()
            let gain = AVAudioUnitEQ(numberOfBands: 0)
            gain.globalGain = 0

            engine.attach(player)
            engine.attach(gain)
            engine.connect(player, to: gain, format: format)
            engine.connect(gain, to: engine.mainMixerNode, format: format)

            players[kind] = player
            gainStages[kind] = gain
            files[kind] = file
            gainsDB[kind] = 0
            loadedKinds.append(kind)

            if case .buffer = source {
                guard let buffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    frameCapacity: AVAudioFrameCount(file.length)
                ) else {
                    throw StemPlayerError("Allocation du buffer impossible pour \(kind.rawValue)")
                }
                try file.read(into: buffer)
                buffers[kind] = buffer
            }
        }

        guard !loadedKinds.isEmpty else { throw StemPlayerError("Aucune piste valide") }
    }

    public func unload() {
        stop()
        for (_, player) in players { engine.detach(player) }
        for (_, gain) in gainStages { engine.detach(gain) }
        players.removeAll()
        gainStages.removeAll()
        files.removeAll()
        buffers.removeAll()
        gainsDB.removeAll()
        mutedKinds.removeAll()
        soloedKinds.removeAll()
        loadedKinds.removeAll()
        totalFrames = 0
        startFrame = 0
    }

    // MARK: - Transport

    /// Démarre les quatre pistes sur un instant commun.
    ///
    /// - Parameter leadIn: délai avant le démarrage. Il doit couvrir le temps
    ///   d'amorçage du moteur : trop court, les premiers nœuds programmés
    ///   partent en retard sur les derniers.
    public func play(fromFrame frame: AVAudioFramePosition = 0, leadIn: TimeInterval = 0.25) throws {
        guard !loadedKinds.isEmpty else { throw StemPlayerError("Rien à lire") }

        startFrame = max(0, min(frame, totalFrames))

        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }

        for kind in loadedKinds {
            try schedule(kind: kind, fromFrame: startFrame)
        }

        // Un seul AVAudioTime, partagé par les quatre nœuds : c'est ce qui rend
        // le départ commun à l'échantillon près. Le temps hôte évite de dépendre
        // de `lastRenderTime`, encore nil juste après le démarrage du moteur.
        let start = AVAudioTime(
            hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: leadIn)
        )
        for kind in loadedKinds {
            players[kind]?.play(at: start)
        }
    }

    private func schedule(kind: StemKind, fromFrame frame: AVAudioFramePosition) throws {
        guard let player = players[kind] else { return }
        player.stop()

        if let buffer = buffers[kind] {
            if frame == 0 {
                player.scheduleBuffer(buffer, at: nil)
            } else {
                guard let slice = buffer.slice(fromFrame: frame) else {
                    throw StemPlayerError("Découpe du buffer impossible pour \(kind.rawValue)")
                }
                player.scheduleBuffer(slice, at: nil)
            }
        } else if let file = files[kind] {
            let remaining = file.length - frame
            guard remaining > 0 else { return }
            player.scheduleSegment(
                file,
                startingFrame: frame,
                frameCount: AVAudioFrameCount(remaining),
                at: nil
            )
        }
    }

    public func pause() {
        for kind in loadedKinds { players[kind]?.pause() }
    }

    public func resume() {
        // Les nœuds reprennent ensemble : `pause` fige la position de chacun,
        // et le moteur les relance sur le même cycle de rendu.
        for kind in loadedKinds { players[kind]?.play() }
    }

    public func stop() {
        for kind in loadedKinds { players[kind]?.stop() }
        if engine.isRunning { engine.stop() }
    }

    /// Repositionne les quatre pistes. Un seek impose de tout reprogrammer :
    /// c'est le seul moment où la synchronisation est réellement reconstruite,
    /// donc le cas à surveiller de près sur l'appareil.
    public func seek(toFrame frame: AVAudioFramePosition, leadIn: TimeInterval = 0.15) throws {
        let wasRunning = engine.isRunning
        for kind in loadedKinds { players[kind]?.stop() }
        if wasRunning {
            try play(fromFrame: frame, leadIn: leadIn)
        } else {
            startFrame = max(0, min(frame, totalFrames))
        }
    }

    // MARK: - Mixage

    /// Gain en dB, appliqué par l'étage EQ. Borné à la plage du schéma.
    public func setGain(_ dB: Float, for kind: StemKind) {
        let clamped = max(-60, min(12, dB))
        gainsDB[kind] = clamped
        gainStages[kind]?.globalGain = clamped
    }

    public func gain(for kind: StemKind) -> Float { gainsDB[kind] ?? 0 }

    /// Mute par mise à zéro du volume — **jamais** par `stop()` ou `pause()`,
    /// qui sortiraient la piste du cycle de rendu et casseraient la synchro.
    public func setMuted(_ muted: Bool, for kind: StemKind) {
        if muted { mutedKinds.insert(kind) } else { mutedKinds.remove(kind) }
        applyAudibility()
    }

    public func isMuted(_ kind: StemKind) -> Bool { mutedKinds.contains(kind) }

    public func setSoloed(_ soloed: Bool, for kind: StemKind) {
        if soloed { soloedKinds.insert(kind) } else { soloedKinds.remove(kind) }
        applyAudibility()
    }

    public func isSoloed(_ kind: StemKind) -> Bool { soloedKinds.contains(kind) }

    private func applyAudibility() {
        for kind in loadedKinds {
            let silencedBySolo = !soloedKinds.isEmpty && !soloedKinds.contains(kind)
            let audible = !mutedKinds.contains(kind) && !silencedBySolo
            players[kind]?.volume = audible ? 1 : 0
        }
    }

    // MARK: - Instrumentation

    /// Position de lecture d'une piste, en frames depuis le début du morceau.
    public func elapsedFrames(for kind: StemKind) -> AVAudioFramePosition? {
        guard let player = players[kind],
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime)
        else { return nil }
        return startFrame + playerTime.sampleTime
    }

    /// Écart maximal entre les pistes, en frames.
    ///
    /// Les quatre nœuds partagent une seule horloge de rendu : le résultat
    /// attendu est **zéro**. Une valeur non nulle signifierait que
    /// l'hypothèse sur laquelle repose tout l'éditeur est fausse — d'où la
    /// place de cette mesure en Phase 1 et non en Phase 3.
    public func driftFrames() -> AVAudioFramePosition? {
        let positions = loadedKinds.compactMap { elapsedFrames(for: $0) }
        guard positions.count == loadedKinds.count, let low = positions.min(),
              let high = positions.max()
        else { return nil }
        return high - low
    }

    public func driftMilliseconds() -> Double? {
        guard let frames = driftFrames() else { return nil }
        return Double(frames) / sampleRate * 1_000
    }

    public var isPlaying: Bool {
        loadedKinds.contains { players[$0]?.isPlaying == true }
    }
}

private extension AVAudioPCMBuffer {
    /// Sous-buffer à partir d'une position, pour le seek en mode `.buffer`.
    func slice(fromFrame frame: AVAudioFramePosition) -> AVAudioPCMBuffer? {
        let offset = AVAudioFrameCount(max(0, frame))
        guard offset < frameLength,
              let slice = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: frameLength - offset
              )
        else { return nil }

        let channels = Int(format.channelCount)
        let frames = Int(frameLength - offset)

        guard let source = floatChannelData, let destination = slice.floatChannelData else {
            return nil
        }
        for channel in 0..<channels {
            destination[channel].update(
                from: source[channel].advanced(by: Int(offset)),
                count: frames
            )
        }
        slice.frameLength = frameLength - offset
        return slice
    }
}
