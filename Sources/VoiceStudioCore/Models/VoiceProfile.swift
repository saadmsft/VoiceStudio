import Foundation

public struct VoiceProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var subtitle: String
    public var isBuiltIn: Bool

    /// Real-time pitch shift in cents (-300 = -3.0 semitones, 0 = natural, +150 = +1.5 semitones)
    public var pitchCents: Float

    /// Sub-harmonic chest exciter & subtle warm tube saturation (0.0 ... 1.0)
    public var subWarmth: Float

    /// High-pass rumble cut frequency in Hz (40 ... 150 Hz)
    public var lowCutHz: Float

    /// Low-mid studio proximity warmth @ 125 Hz (-3 ... +9 dB)
    public var chestWarmthDb: Float

    /// Anti-boxiness mud cut @ 310 Hz (0 ... 6 dB of cut)
    public var mudCutDb: Float

    /// Vocal articulation & clarity boost @ 4.2 kHz (-3 ... +9 dB)
    public var presenceDb: Float

    /// Studio condenser high-shelf shimmer @ 9.5 kHz (-3 ... +10 dB)
    public var airDb: Float

    /// Dynamic sibilance tamer around 6.5 kHz (0.0 ... 1.0)
    public var deEsserAmount: Float

    /// Broadcast leveling & density compression (0.0 ... 1.0)
    public var compressionAmount: Float

    /// Background room noise gate toggle & threshold (-80 ... -25 dB)
    public var gateEnabled: Bool
    public var gateThresholdDb: Float

    /// Input mic pre-gain (-12 ... +18 dB) and final studio output trim (-12 ... +12 dB)
    public var inputGainDb: Float
    public var outputGainDb: Float

    public init(
        id: String = UUID().uuidString,
        name: String,
        subtitle: String = "Custom Profile",
        isBuiltIn: Bool = false,
        pitchCents: Float = -65,
        subWarmth: Float = 0.24,
        lowCutHz: Float = 80,
        chestWarmthDb: Float = 3.5,
        mudCutDb: Float = 2.5,
        presenceDb: Float = 3.8,
        airDb: Float = 4.5,
        deEsserAmount: Float = 0.35,
        compressionAmount: Float = 0.55,
        gateEnabled: Bool = true,
        gateThresholdDb: Float = -52,
        inputGainDb: Float = 0.0,
        outputGainDb: Float = 1.5
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.isBuiltIn = isBuiltIn
        self.pitchCents = pitchCents
        self.subWarmth = subWarmth
        self.lowCutHz = lowCutHz
        self.chestWarmthDb = chestWarmthDb
        self.mudCutDb = mudCutDb
        self.presenceDb = presenceDb
        self.airDb = airDb
        self.deEsserAmount = deEsserAmount
        self.compressionAmount = compressionAmount
        self.gateEnabled = gateEnabled
        self.gateThresholdDb = gateThresholdDb
        self.inputGainDb = inputGainDb
        self.outputGainDb = outputGainDb
    }

    public var semitonesFormatted: String {
        let st = pitchCents / 100.0
        if abs(st) < 0.01 { return "0.00 st" }
        return String(format: "%+.2f st", st)
    }

    /// Computes approximate combined EQ curve response (dB) at `freq` Hz for UI visualization.
    public func magnitudeResponseDb(at freq: Double) -> Double {
        let f = max(20.0, min(20000.0, freq))

        // 2nd-order High-Pass response at lowCutHz
        let fc = Double(lowCutHz)
        let ratio = fc / f
        let hpfMagSq = 1.0 / (1.0 + pow(ratio, 4.0))
        let hpfDb = 10.0 * log10(max(hpfMagSq, 1e-6))

        // Bell filter approximation in log-frequency space
        func bell(_ center: Double, gainDb: Double, q: Double) -> Double {
            guard abs(gainDb) > 0.01 else { return 0.0 }
            let octaves = log2(f / center)
            let bw = 1.0 / max(0.35, q)
            return gainDb * exp(-0.5 * pow(octaves / (bw * 0.55), 2.0))
        }

        // High-shelf approximation around 9500 Hz
        let shelfTransition = 1.0 / (1.0 + exp(-3.4 * log2(f / 9500.0)))
        let airShelfDb = Double(airDb) * shelfTransition

        let chest = bell(125.0, gainDb: Double(chestWarmthDb) + Double(subWarmth) * 2.0, q: 1.0)
        let mud = bell(310.0, gainDb: -Double(mudCutDb), q: 1.6)
        let presence = bell(4200.0, gainDb: Double(presenceDb), q: 1.15)

        return max(-18.0, min(14.0, hpfDb + chest + mud + presence + airShelfDb))
    }

    // MARK: - Built-in Studio Presets

    public static let teamsCrispAndDeep = VoiceProfile(
        id: "builtin-teams-crisp-deep",
        name: "Teams Crisp & Deep",
        subtitle: "Crisp condenser sheen + subtle authoritative depth",
        isBuiltIn: true,
        pitchCents: -65,
        subWarmth: 0.24,
        lowCutHz: 80,
        chestWarmthDb: 3.5,
        mudCutDb: 2.5,
        presenceDb: 3.8,
        airDb: 4.5,
        deEsserAmount: 0.35,
        compressionAmount: 0.55,
        gateEnabled: true,
        gateThresholdDb: -52,
        inputGainDb: 0.0,
        outputGainDb: 1.5
    )

    public static let podcastBroadcast = VoiceProfile(
        id: "builtin-podcast-sm7b",
        name: "Podcast Studio",
        subtitle: "Warm FM radio / Shure SM7B close-mic tone",
        isBuiltIn: true,
        pitchCents: -50,
        subWarmth: 0.32,
        lowCutHz: 75,
        chestWarmthDb: 4.6,
        mudCutDb: 3.0,
        presenceDb: 3.2,
        airDb: 3.8,
        deEsserAmount: 0.42,
        compressionAmount: 0.68,
        gateEnabled: true,
        gateThresholdDb: -50,
        inputGainDb: 0.0,
        outputGainDb: 2.0
    )

    public static let subtleNaturalPolish = VoiceProfile(
        id: "builtin-natural-polish",
        name: "Natural Studio",
        subtitle: "Zero pitch shift — pure studio EQ & leveling",
        isBuiltIn: true,
        pitchCents: 0,
        subWarmth: 0.14,
        lowCutHz: 80,
        chestWarmthDb: 2.6,
        mudCutDb: 2.2,
        presenceDb: 3.5,
        airDb: 4.2,
        deEsserAmount: 0.30,
        compressionAmount: 0.48,
        gateEnabled: true,
        gateThresholdDb: -54,
        inputGainDb: 0.0,
        outputGainDb: 1.0
    )

    public static let executiveBaritone = VoiceProfile(
        id: "builtin-exec-baritone",
        name: "Deep Baritone",
        subtitle: "Deeper chest resonance & commanding presence",
        isBuiltIn: true,
        pitchCents: -115,
        subWarmth: 0.36,
        lowCutHz: 72,
        chestWarmthDb: 4.8,
        mudCutDb: 3.2,
        presenceDb: 4.0,
        airDb: 4.0,
        deEsserAmount: 0.38,
        compressionAmount: 0.62,
        gateEnabled: true,
        gateThresholdDb: -50,
        inputGainDb: 0.0,
        outputGainDb: 1.8
    )

    public static let crystalClear = VoiceProfile(
        id: "builtin-crystal-clear",
        name: "Crystal Crisp",
        subtitle: "Maximum clarity & articulation on calls",
        isBuiltIn: true,
        pitchCents: -30,
        subWarmth: 0.10,
        lowCutHz: 95,
        chestWarmthDb: 1.8,
        mudCutDb: 3.0,
        presenceDb: 5.0,
        airDb: 5.6,
        deEsserAmount: 0.48,
        compressionAmount: 0.58,
        gateEnabled: true,
        gateThresholdDb: -48,
        inputGainDb: 0.0,
        outputGainDb: 1.5
    )

    public static let builtInPresets: [VoiceProfile] = [
        .teamsCrispAndDeep,
        .podcastBroadcast,
        .subtleNaturalPolish,
        .executiveBaritone,
        .crystalClear
    ]
}
