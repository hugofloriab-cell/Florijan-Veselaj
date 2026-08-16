import AVFoundation

/// Génère quatre pistes de test, pour que le spike tourne avant même que le
/// moteur musical soit choisi.
///
/// Chaque piste porte un timbre distinct **et** un même clic bref à chaque
/// seconde pleine. Les clics étant simultanés par construction, la moindre
/// désynchronisation s'entend comme un flam — la mesure est chiffrée, mais
/// l'oreille reste le juge d'appel.
public enum TestStems {

    public static func generate(
        into directory: URL,
        duration: TimeInterval = 180,
        sampleRate: Double = 44_100
    ) throws -> [StemKind: URL] {

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let toneByKind: [StemKind: Double] = [
            .vocals: 440,
            .drums: 0,      // percussif : uniquement les clics
            .bass: 110,
            .other: 660,
        ]

        var urls: [StemKind: URL] = [:]

        for kind in StemKind.allCases {
            let url = directory.appendingPathComponent("\(kind.rawValue).wav")
            try write(
                toneHz: toneByKind[kind] ?? 0,
                duration: duration,
                sampleRate: sampleRate,
                to: url
            )
            urls[kind] = url
        }

        return urls
    }

    private static func write(
        toneHz: Double,
        duration: TimeInterval,
        sampleRate: Double,
        to url: URL
    ) throws {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        ) else {
            throw StemPlayerError("Format de génération invalide")
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
        )

        let chunkFrames = AVAudioFrameCount(sampleRate) // 1 s par écriture
        let totalFrames = AVAudioFramePosition(duration * sampleRate)
        var written: AVAudioFramePosition = 0

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw StemPlayerError("Allocation du buffer de génération impossible")
        }

        let clickFrames = Int(sampleRate * 0.005) // clic de 5 ms
        let twoPi = 2 * Double.pi

        while written < totalFrames {
            let frames = Int(min(AVAudioFramePosition(chunkFrames), totalFrames - written))
            buffer.frameLength = AVAudioFrameCount(frames)

            guard let channels = buffer.floatChannelData else {
                throw StemPlayerError("Buffer sans données flottantes")
            }

            for frame in 0..<frames {
                let absoluteFrame = Int(written) + frame
                var sample: Float = 0

                if toneHz > 0 {
                    let phase = twoPi * toneHz * Double(absoluteFrame) / sampleRate
                    sample += Float(sin(phase)) * 0.2
                }

                // Clic sur chaque seconde pleine, identique sur les quatre pistes.
                let positionInSecond = absoluteFrame % Int(sampleRate)
                if positionInSecond < clickFrames {
                    let decay = 1 - Float(positionInSecond) / Float(clickFrames)
                    let phase = twoPi * 1_000 * Double(absoluteFrame) / sampleRate
                    sample += Float(sin(phase)) * 0.5 * decay
                }

                channels[0][frame] = sample
                channels[1][frame] = sample
            }

            try file.write(from: buffer)
            written += AVAudioFramePosition(frames)
        }
    }
}
