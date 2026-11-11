import Foundation

/// Zero-allocation biquad filter state & coefficients for real-time per-sample DSP.
public struct BiquadFilter: Sendable {
    private var b0: Float = 1.0
    private var b1: Float = 0.0
    private var b2: Float = 0.0
    private var a1: Float = 0.0
    private var a2: Float = 0.0

    private var z1: Float = 0.0
    private var z2: Float = 0.0

    public init() {}

    public mutating func reset() {
        z1 = 0
        z2 = 0
    }

    public mutating func setBandpass(sampleRate: Float, centerHz: Float, q: Float) {
        let w0 = 2.0 * Float.pi * max(20.0, min(sampleRate * 0.45, centerHz)) / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * max(0.1, q))
        let a0 = 1.0 + alpha
        b0 = alpha / a0
        b1 = 0.0
        b2 = -alpha / a0
        a1 = (-2.0 * cosW0) / a0
        a2 = (1.0 - alpha) / a0
    }

    public mutating func setLowpass(sampleRate: Float, cutoffHz: Float, q: Float = 0.7071) {
        let w0 = 2.0 * Float.pi * max(20.0, min(sampleRate * 0.45, cutoffHz)) / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * max(0.1, q))
        let a0 = 1.0 + alpha
        b0 = ((1.0 - cosW0) * 0.5) / a0
        b1 = (1.0 - cosW0) / a0
        b2 = ((1.0 - cosW0) * 0.5) / a0
        a1 = (-2.0 * cosW0) / a0
        a2 = (1.0 - alpha) / a0
    }

    @inline(__always)
    public mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}

/// Broadcast Sub-Harmonic Chest Exciter + Subtle Warm Tube Saturation.
/// Tracks vocal fundamental zero-crossings (90-185 Hz), synthesizes a clean octave-down
/// band-limited chest harmonic (55-115 Hz), and adds subtle warm harmonic density.
public struct SubHarmonicExciter: Sendable {
    private var fundamentalBP = BiquadFilter()
    private var subLP = BiquadFilter()
    private var prevBandSample: Float = 0.0
    private var subFlipFlop: Float = 1.0
    private var envFollower: Float = 0.0

    public init(sampleRate: Float = 48000.0) {
        fundamentalBP.setBandpass(sampleRate: sampleRate, centerHz: 135.0, q: 1.2)
        subLP.setLowpass(sampleRate: sampleRate, cutoffHz: 112.0, q: 0.75)
    }

    public mutating func reset() {
        fundamentalBP.reset()
        subLP.reset()
        prevBandSample = 0.0
        subFlipFlop = 1.0
        envFollower = 0.0
    }

    @inline(__always)
    public mutating func process(_ x: Float, amount: Float) -> Float {
        guard amount > 0.005 else { return x }

        // 1. Isolate vocal fundamental
        let fund = fundamentalBP.process(x)
        if prevBandSample <= 0.0 && fund > 0.0 {
            subFlipFlop = -subFlipFlop
        }
        prevBandSample = fund

        // Smooth envelope of fundamental so sub-harmonic breathes naturally with speech
        let absFund = abs(fund)
        let coeff: Float = absFund > envFollower ? 0.025 : 0.0025
        envFollower += coeff * (absFund - envFollower)

        let rawSub = subFlipFlop * envFollower
        let cleanSub = subLP.process(rawSub)

        // 2. Subtle warm tube saturation (even + odd harmonics)
        let drive: Float = 1.0 + amount * 1.15
        let biased = x * drive + 0.02 * amount
        let saturated = (tanh(biased) - tanh(0.02 * amount)) / tanh(drive)

        let warmed = x * (1.0 - amount * 0.35) + saturated * (amount * 0.35)
        return warmed + cleanSub * (amount * 0.34)
    }
}

/// Real-time Split-Band Dynamic De-Esser centered around vocal sibilance (6.5 kHz).
/// Keeps crispness/air silky without harsh "S" and "SH" spikes on voice calls & streams.
public struct DynamicDeEsser: Sendable {
    private var sibilanceBP = BiquadFilter()
    private var sibEnv: Float = 0.0
    private var fullEnv: Float = 0.0
    private var gainReduction: Float = 1.0

    public init(sampleRate: Float = 48000.0) {
        sibilanceBP.setBandpass(sampleRate: sampleRate, centerHz: 6600.0, q: 1.4)
    }

    public mutating func reset() {
        sibilanceBP.reset()
        sibEnv = 0.0
        fullEnv = 0.0
        gainReduction = 1.0
    }

    @inline(__always)
    public mutating func process(_ x: Float, amount: Float) -> Float {
        guard amount > 0.01 else { return x }

        let sibBand = sibilanceBP.process(x)
        let absSib = abs(sibBand)
        let absFull = abs(x)

        sibEnv += (absSib > sibEnv ? 0.06 : 0.003) * (absSib - sibEnv)
        fullEnv += (absFull > fullEnv ? 0.03 : 0.002) * (absFull - fullEnv)

        // Detect when sibilant energy dominates vocal energy above noise floor
        var targetSibGain: Float = 1.0
        if sibEnv > 0.004 && sibEnv > fullEnv * 0.32 {
            let excess = min(1.0, (sibEnv / max(0.004, fullEnv * 0.32) - 1.0) * 0.65)
            targetSibGain = max(1.0 - amount * 0.78, 1.0 - excess * amount * 0.85)
        }

        let smoothCoeff: Float = targetSibGain < gainReduction ? 0.08 : 0.004
        gainReduction += smoothCoeff * (targetSibGain - gainReduction)

        // Subtract attenuated portion of sibilance band only (leaves mids/bass untouched!)
        let sibCut = (1.0 - gainReduction) * sibBand
        return x - sibCut
    }
}

/// Transparent Broadcast Brickwall Soft-Clip Limiter (-0.7 dBFS ceiling).
public struct SoftClipLimiter: Sendable {
    public init() {}

    @inline(__always)
    public func process(_ x: Float) -> Float {
        let ceiling: Float = 0.92 // ~ -0.72 dBFS
        let knee: Float = 0.65
        let ax = abs(x)
        if ax <= knee {
            return x
        }
        let sign: Float = x >= 0 ? 1.0 : -1.0
        let span = ceiling - knee
        let compressed = knee + span * tanh((ax - knee) / max(0.05, span))
        return sign * min(ceiling, compressed)
    }
}
