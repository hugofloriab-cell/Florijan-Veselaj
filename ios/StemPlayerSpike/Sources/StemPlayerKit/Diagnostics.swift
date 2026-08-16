import Darwin
import Foundation

/// Sondes de mesure du spike. Rien ici ne sert à la lecture : uniquement à
/// produire les chiffres qui alimenteront l'ADR.
public enum Diagnostics {

    /// Mémoire résidente du processus, en octets.
    ///
    /// `resident_size` plutôt que `phys_footprint` : c'est ce que rapporte le
    /// débogueur mémoire d'Xcode, donc ce à quoi on comparera à la main.
    public static func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    public static func megabytes(_ bytes: UInt64) -> Double {
        Double(bytes) / 1_048_576
    }
}

/// Résultat complet d'une passe de mesure, prêt à être recopié dans l'ADR.
public struct SpikeReport: Sendable {
    public var source: String
    public var stemCount: Int
    public var durationSeconds: TimeInterval
    public var memoryBeforeLoadMB: Double
    public var memoryAfterLoadMB: Double
    public var peakMemoryMB: Double
    public var maxDriftFrames: Int64
    public var maxDriftMilliseconds: Double
    public var driftAfterSeekFrames: Int64
    public var mixdownRealtimeFactor: Double?

    public var memoryCostOfStemsMB: Double { memoryAfterLoadMB - memoryBeforeLoadMB }

    /// Seuils de décision. En dessous, l'UX de l'éditeur telle qu'elle est
    /// prévue en Phase 3 tient ; au-dessus, elle est à repenser.
    public var verdict: String {
        var failures: [String] = []
        if maxDriftMilliseconds > 1 {
            failures.append("dérive \(String(format: "%.2f", maxDriftMilliseconds)) ms > 1 ms")
        }
        if driftAfterSeekFrames > 0 {
            failures.append("désynchronisation de \(driftAfterSeekFrames) frames après seek")
        }
        if peakMemoryMB > 150 {
            failures.append("mémoire crête \(String(format: "%.0f", peakMemoryMB)) Mo > 150 Mo")
        }
        if let factor = mixdownRealtimeFactor, factor < 5 {
            failures.append("mixdown \(String(format: "%.1f", factor))× < 5× temps réel")
        }
        return failures.isEmpty ? "PASSE" : "ÉCHEC — " + failures.joined(separator: " ; ")
    }

    public var formatted: String {
        var lines: [String] = []
        lines.append("┌─ Spike n°1 — lecture de \(stemCount) stems (\(source))")
        lines.append(String(format: "│ durée mesurée         %.1f s", durationSeconds))
        lines.append(String(format: "│ mémoire avant charge  %.1f Mo", memoryBeforeLoadMB))
        lines.append(String(format: "│ mémoire après charge  %.1f Mo", memoryAfterLoadMB))
        lines.append(String(format: "│ coût des stems        %.1f Mo", memoryCostOfStemsMB))
        lines.append(String(format: "│ mémoire crête         %.1f Mo", peakMemoryMB))
        lines.append(String(format: "│ dérive max            %lld frames (%.3f ms)",
                            maxDriftFrames, maxDriftMilliseconds))
        lines.append(String(format: "│ dérive après seek     %lld frames", driftAfterSeekFrames))
        if let factor = mixdownRealtimeFactor {
            lines.append(String(format: "│ mixdown hors-ligne    %.1f× temps réel", factor))
        } else {
            lines.append("│ mixdown hors-ligne    non mesuré")
        }
        lines.append("│ VERDICT               \(verdict)")
        lines.append("└─")
        return lines.joined(separator: "\n")
    }
}
