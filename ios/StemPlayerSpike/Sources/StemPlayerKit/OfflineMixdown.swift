import AVFoundation

/// Mixdown hors-ligne des stems vers un fichier unique.
///
/// C'est la vérification de l'affirmation portée par l'ADR 000 : l'export peut
/// être rendu **sur l'appareil**, plus vite que le temps réel, donc à coût cloud
/// nul. Si le facteur mesuré ici est proche de 1×, l'argument tombe et il faut
/// rebasculer l'export côté serveur — avec la facture qui va avec.
public enum OfflineMixdown {

    public struct StemSetting: Sendable {
        public var gainDB: Float
        public var isMuted: Bool

        public init(gainDB: Float = 0, isMuted: Bool = false) {
            self.gainDB = gainDB
            self.isMuted = isMuted
        }
    }

    public struct Result: Sendable {
        /// Durée audio produite.
        public let audioSeconds: TimeInterval
        /// Temps de calcul réellement passé.
        public let wallSeconds: TimeInterval
        public let outputURL: URL

        /// > 1 signifie « plus rapide que le temps réel ».
        public var realtimeFactor: Double {
            wallSeconds > 0 ? audioSeconds / wallSeconds : 0
        }
    }

    /// Rend les pistes vers un WAV 16 bits.
    ///
    /// - Note: le moteur est distinct de celui du lecteur. Basculer un moteur en
    ///   rendu manuel pendant qu'il joue n'aurait aucun sens — le rendu hors-ligne
    ///   n'a pas d'horloge temps réel.
    public static func render(
        urls: [StemKind: URL],
        settings: [StemKind: StemSetting] = [:],
        to outputURL: URL,
        maximumFrameCount: AVAudioFrameCount = 4_096
    ) throws -> Result {

        let engine = AVAudioEngine()
        var players: [AVAudioPlayerNode] = []
        var canonicalFormat: AVAudioFormat?
        var totalFrames: AVAudioFramePosition = 0

        for kind in StemKind.allCases {
            guard let url = urls[kind] else { continue }

            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            if canonicalFormat == nil { canonicalFormat = format }
            totalFrames = max(totalFrames, file.length)

            let player = AVAudioPlayerNode()
            let gain = AVAudioUnitEQ(numberOfBands: 0)
            let setting = settings[kind] ?? StemSetting()
            gain.globalGain = max(-60, min(12, setting.gainDB))

            engine.attach(player)
            engine.attach(gain)
            engine.connect(player, to: gain, format: format)
            engine.connect(gain, to: engine.mainMixerNode, format: format)

            player.volume = setting.isMuted ? 0 : 1
            player.scheduleFile(file, at: nil)
            players.append(player)
        }

        guard let format = canonicalFormat, totalFrames > 0 else {
            throw StemPlayerError("Aucune piste à mixer")
        }

        // Bascule en rendu manuel : le moteur cesse d'être piloté par l'horloge
        // audio et n'avance que quand on l'appelle. C'est ce qui permet d'aller
        // plus vite que le temps réel.
        try engine.enableManualRenderingMode(
            .offline,
            format: format,
            maximumFrameCount: maximumFrameCount
        )

        engine.prepare()
        try engine.start()
        players.forEach { $0.play() }

        guard let renderBuffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        ) else {
            throw StemPlayerError("Allocation du buffer de rendu impossible")
        }

        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
        )

        let startedAt = Date()

        while engine.manualRenderingSampleTime < totalFrames {
            let remaining = totalFrames - engine.manualRenderingSampleTime
            let framesToRender = AVAudioFrameCount(
                min(AVAudioFramePosition(renderBuffer.frameCapacity), remaining)
            )

            switch try engine.renderOffline(framesToRender, to: renderBuffer) {
            case .success:
                try outputFile.write(from: renderBuffer)
            case .insufficientDataFromInputNode:
                // Plus rien à lire : les fichiers sont épuisés avant la cible.
                engine.stop()
                engine.disableManualRenderingMode()
                return Result(
                    audioSeconds: Double(engine.manualRenderingSampleTime) / format.sampleRate,
                    wallSeconds: Date().timeIntervalSince(startedAt),
                    outputURL: outputURL
                )
            case .cannotDoInCurrentContext:
                continue
            case .error:
                throw StemPlayerError("Échec du rendu hors-ligne")
            @unknown default:
                throw StemPlayerError("Statut de rendu inconnu")
            }
        }

        let wallSeconds = Date().timeIntervalSince(startedAt)
        engine.stop()
        engine.disableManualRenderingMode()

        return Result(
            audioSeconds: Double(totalFrames) / format.sampleRate,
            wallSeconds: wallSeconds,
            outputURL: outputURL
        )
    }
}
