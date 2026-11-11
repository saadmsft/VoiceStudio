import SwiftUI
import VoiceStudioCore

// MARK: - Studio Theme Palette

enum StudioTheme {
    static let bgDeep = Color(red: 0.055, green: 0.065, blue: 0.090)
    static let panelBg = Color(red: 0.092, green: 0.108, blue: 0.145)
    static let cardBg = Color(red: 0.118, green: 0.138, blue: 0.182)
    static let border = Color.white.opacity(0.08)
    static let accentCyan = Color(red: 0.22, green: 0.78, blue: 0.98)
    static let accentAmber = Color(red: 0.98, green: 0.68, blue: 0.22)
    static let accentEmerald = Color(red: 0.18, green: 0.86, blue: 0.56)
    static let accentCoral = Color(red: 0.98, green: 0.34, blue: 0.38)
}

// MARK: - Live Studio EQ & Pitch Response Visualizer

struct EQCurveVisualizer: View {
    let profile: VoiceProfile
    let isBypassed: Bool

    private let freqLabels: [(Double, String)] = [
        (50, "50"),
        (125, "125"),
        (310, "310"),
        (1000, "1k"),
        (4200, "4.2k"),
        (10000, "10k")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("LIVE STUDIO TONE & EQ CURVE", systemImage: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 8) {
                    Text("PITCH \(profile.semitonesFormatted)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(StudioTheme.accentAmber.opacity(0.16))
                        .foregroundStyle(StudioTheme.accentAmber)
                        .clipShape(Capsule())

                    Text("WARMTH \(Int(profile.subWarmth * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(StudioTheme.accentCyan.opacity(0.16))
                        .foregroundStyle(StudioTheme.accentCyan)
                        .clipShape(Capsule())
                }
            }

            ZStack {
                Canvas { context, size in
                    let minLog = log10(25.0)
                    let maxLog = log10(18000.0)
                    let midY = size.height * 0.54
                    let dbScale = (size.height * 0.40) / 12.0 // +/- 12 dB range

                    func xForFreq(_ f: Double) -> CGFloat {
                        let norm = (log10(f) - minLog) / (maxLog - minLog)
                        return CGFloat(norm) * size.width
                    }

                    func yForDb(_ db: Double) -> CGFloat {
                        midY - CGFloat(db) * dbScale
                    }

                    // Horizontal dB grid lines (+6, 0, -6)
                    for db in [-6.0, 0.0, 6.0] {
                        let y = yForDb(db)
                        var gridPath = Path()
                        gridPath.move(to: CGPoint(x: 0, y: y))
                        gridPath.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(
                            gridPath,
                            with: .color(.white.opacity(db == 0 ? 0.16 : 0.06)),
                            lineWidth: db == 0 ? 1.0 : 0.7
                        )
                    }

                    // Vertical frequency marker lines
                    for (freq, _) in freqLabels {
                        let x = xForFreq(freq)
                        var vPath = Path()
                        vPath.move(to: CGPoint(x: x, y: 0))
                        vPath.addLine(to: CGPoint(x: x, y: size.height - 16))
                        context.stroke(vPath, with: .color(.white.opacity(0.05)), lineWidth: 0.7)
                    }

                    // Sample response curve
                    let steps = 160
                    var linePath = Path()
                    var fillPath = Path()

                    for i in 0...steps {
                        let t = Double(i) / Double(steps)
                        let freq = pow(10.0, minLog + t * (maxLog - minLog))
                        let db = isBypassed ? 0.0 : profile.magnitudeResponseDb(at: freq)
                        let pt = CGPoint(x: CGFloat(t) * size.width, y: yForDb(db))
                        if i == 0 {
                            linePath.move(to: pt)
                            fillPath.move(to: CGPoint(x: 0, y: midY))
                            fillPath.addLine(to: pt)
                        } else {
                            linePath.addLine(to: pt)
                            fillPath.addLine(to: pt)
                        }
                    }
                    fillPath.addLine(to: CGPoint(x: size.width, y: midY))
                    fillPath.closeSubpath()

                    let activeColor = isBypassed ? Color.gray : StudioTheme.accentCyan
                    context.fill(
                        fillPath,
                        with: .linearGradient(
                            Gradient(colors: [
                                activeColor.opacity(0.30),
                                StudioTheme.accentAmber.opacity(0.08),
                                .clear
                            ]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: 0, y: size.height)
                        )
                    )

                    context.stroke(
                        linePath,
                        with: .linearGradient(
                            Gradient(colors: isBypassed ? [.gray] : [StudioTheme.accentAmber, StudioTheme.accentCyan]),
                            startPoint: CGPoint(x: 0, y: midY),
                            endPoint: CGPoint(x: size.width, y: midY)
                        ),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                    )
                }

                VStack {
                    Spacer()
                    HStack {
                        ForEach(freqLabels, id: \.0) { _, label in
                            Text(label)
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.38))
                            if label != freqLabels.last?.1 {
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 3)
                }

                if isBypassed {
                    Text("FX BYPASSED (RAW MIC)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }
            .frame(height: 104)
            .background(StudioTheme.bgDeep.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )
        }
    }
}

// MARK: - Studio Parameter Slider Row (with Click Badge to Reset)

struct StudioSliderRow: View {
    let title: String
    let hint: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let defaultValue: Float
    let accent: Color
    let formatter: (Float) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Button {
                    value = defaultValue
                } label: {
                    Text(formatter(value))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(accent.opacity(0.13))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Click to reset \(title) to default")
            }

            Slider(value: $value, in: range)
                .tint(accent)
                .controlSize(.small)
                .padding(.horizontal, 2)
        }
    }
}

// MARK: - Segmented Broadcast LED Level Meter

struct VerticalLEDMeter: View {
    let label: String
    let dbValue: Float
    let isGainReduction: Bool

    private let segmentCount = 20

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let segHeight = max(2.0, (geo.size.height - CGFloat(segmentCount - 1) * 2.0) / CGFloat(segmentCount))
                VStack(spacing: 2) {
                    ForEach(0..<segmentCount, id: \.self) { idx in
                        let normalizedFromTop = Float(idx) / Float(segmentCount - 1)
                        let lit = isSegmentLit(normalizedFromTop: normalizedFromTop)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(segmentColor(normalizedFromTop: normalizedFromTop).opacity(lit ? 0.95 : 0.14))
                            .frame(height: segHeight)
                    }
                }
            }
            .frame(width: 16)

            Text(label)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func isSegmentLit(normalizedFromTop: Float) -> Bool {
        if isGainReduction {
            // Gain reduction lights from top downward (0 .. 18 dB)
            let grNorm = min(1.0, max(0.0, dbValue / 16.0))
            return normalizedFromTop < grNorm && dbValue > 0.3
        } else {
            // Standard VU meter (-58 dB bottom .. 0 dB top)
            let levelFromBottom = 1.0 - normalizedFromTop
            let meterNorm = min(1.0, max(0.0, (dbValue + 58.0) / 58.0))
            return levelFromBottom <= meterNorm
        }
    }

    private func segmentColor(normalizedFromTop: Float) -> Color {
        if isGainReduction {
            return StudioTheme.accentAmber
        }
        if normalizedFromTop < 0.12 {
            return StudioTheme.accentCoral // > -6 dB peak zone
        } else if normalizedFromTop < 0.32 {
            return StudioTheme.accentAmber // -18 .. -6 dB sweet spot
        } else {
            return StudioTheme.accentEmerald
        }
    }
}
