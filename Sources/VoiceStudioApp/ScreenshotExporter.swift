import AVFoundation
import AppKit
import SwiftUI
import VoiceStudioCore

@MainActor
enum ScreenshotExporter {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments

        if let wavIdx = args.firstIndex(of: "--process-wav"), wavIdx + 3 < args.count {
            let inPath = args[wavIdx + 1]
            let rawOutPath = args[wavIdx + 2]
            let studioOutPath = args[wavIdx + 3]
            processWavThroughStudioEngine(inputPath: inPath, rawOutPath: rawOutPath, studioOutPath: studioOutPath)
            return true
        }

        guard let idx = args.firstIndex(of: "--export-screenshots"), idx + 1 < args.count else {
            return false
        }
        let outDir = args[idx + 1]
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        // 1. Main Studio Console ("Studio Crisp & Deep")
        let vm1 = StudioViewModel(screenshotPreviewMode: true)
        renderFramedScreenshot(
            title: "VoiceStudio — macOS Broadcast Voice Rack",
            showTrafficLights: true,
            contentSize: CGSize(width: 980, height: 760),
            to: "\(outDir)/screenshot-main-rack.png"
        ) {
            MainStudioView(vm: vm1)
        }

        // 2. Deep Baritone + Feedback-Free 5s Loop & Tweak Mode Active
        let vm2 = StudioViewModel(screenshotPreviewMode: true)
        vm2.profile = .executiveBaritone
        vm2.hasRecordedCheck = true
        vm2.isPlayingCheckLoop = true
        vm2.liveMonitorEnabled = true
        vm2.meters.inputMeterDb = -10.5
        vm2.meters.gainReductionDb = 6.4
        vm2.meters.outputMeterDb = -4.8
        renderFramedScreenshot(
            title: "VoiceStudio — Deep Baritone • Loop & Tweak Active",
            showTrafficLights: true,
            contentSize: CGSize(width: 980, height: 760),
            to: "\(outDir)/screenshot-baritone-loop.png"
        ) {
            MainStudioView(vm: vm2)
        }

        // 3. macOS Menu Bar Quick Controller Popover
        let vm3 = StudioViewModel(screenshotPreviewMode: true)
        renderFramedScreenshot(
            title: "macOS Menu Bar Companion",
            showTrafficLights: false,
            contentSize: CGSize(width: 310, height: 345),
            to: "\(outDir)/screenshot-menubar.png"
        ) {
            MenuBarPopoverView(vm: vm3)
                .background(Color(red: 0.11, green: 0.13, blue: 0.18))
                .preferredColorScheme(.dark)
        }

        // 4. GitHub Social Preview Card (Exact 1280x640 OpenGraph standard)
        renderExactCanvasView(size: CGSize(width: 1280, height: 640), to: "\(outDir)/social-preview.png") {
            SocialPreviewCardView()
        }

        // 5. Video Frame A (Raw Bypassed) & Video Frame B (Studio FX Active)
        let vmRaw = StudioViewModel(screenshotPreviewMode: true)
        vmRaw.isBypassed = true
        vmRaw.statusMessage = "FX BYPASSED • Hearing Untreated Thin Laptop Mic"
        vmRaw.meters.inputMeterDb = -21.0
        vmRaw.meters.gainReductionDb = 0.0
        vmRaw.meters.outputMeterDb = -21.0
        renderExactCanvasView(size: CGSize(width: 1280, height: 720), to: "\(outDir)/video-frame-raw.png") {
            DemoVideoFrameView(
                badgeText: "BEFORE • RAW LAPTOP MIC (FX BYPASSED)",
                badgeColor: StudioTheme.accentCoral,
                subtitle: "Thin low-end, 310 Hz boxy room resonance, uneven volume",
                vm: vmRaw
            )
        }

        let vmFX = StudioViewModel(screenshotPreviewMode: true)
        vmFX.profile = .studioCrispAndDeep
        vmFX.meters.inputMeterDb = -14.0
        vmFX.meters.gainReductionDb = 4.8
        vmFX.meters.outputMeterDb = -5.5
        renderExactCanvasView(size: CGSize(width: 1280, height: 720), to: "\(outDir)/video-frame-studio.png") {
            DemoVideoFrameView(
                badgeText: "AFTER • VOICESTUDIO ON AIR (STUDIO CRISP & DEEP)",
                badgeColor: StudioTheme.accentEmerald,
                subtitle: "-0.65 st Depth • Sub-Harmonic Chest Body • 4.2k Crispness • 9.5k Condenser Air",
                vm: vmFX
            )
        }

        print("Exported screenshots & social/video cards to \(outDir)")
        return true
    }

    private static func processWavThroughStudioEngine(inputPath: String, rawOutPath: String, studioOutPath: String) {
        do {
            let inURL = URL(fileURLWithPath: inputPath)
            let inFile = try AVAudioFile(forReading: inURL)
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1) else { return }
            let frameCount = AVAudioFrameCount(inFile.length)
            guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
            try inFile.read(into: pcm)

            let count = Int(pcm.frameLength)
            guard let ch0 = pcm.floatChannelData?[0] else { return }

            // Simulate untreated thin/boxy laptop mic with faint room floor for realistic "Before" source
            var boxyBP = BiquadFilter()
            boxyBP.setBandpass(sampleRate: 48000, centerHz: 340, q: 1.4)
            var dullLP = BiquadFilter()
            dullLP.setLowpass(sampleRate: 48000, cutoffHz: 4600, q: 0.707)
            var prevX: Float = 0.0
            var thinHPState: Float = 0.0

            var rawLaptopMic = [Float](repeating: 0.0, count: count)
            for i in 0..<count {
                let x = ch0[i]
                // 1st-order highpass around 190 Hz (removes natural chest bass on tiny laptop mics)
                thinHPState = 0.975 * (thinHPState + x - prevX)
                prevX = x
                let boxy = boxyBP.process(thinHPState) * 0.55
                let dulled = dullLP.process(thinHPState * 0.62 + boxy)
                rawLaptopMic[i] = max(-0.95, min(0.95, dulled))
            }

            // Write Raw "Before" WAV
            let rawURL = URL(fileURLWithPath: rawOutPath)
            try? FileManager.default.removeItem(at: rawURL)
            let rawFile = try AVAudioFile(forWriting: rawURL, settings: format.settings)
            guard let rawPCM = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return }
            rawPCM.frameLength = AVAudioFrameCount(count)
            if let rCh = rawPCM.floatChannelData?[0] {
                for i in 0..<count { rCh[i] = rawLaptopMic[i] }
            }
            try rawFile.write(from: rawPCM)

            // Pad 4800 zero samples at front to absorb TimePitch FFT warmup, then run full VoiceStudioEngine DSP!
            let warmup = 4800
            var samples = [Float](repeating: 0.0, count: warmup + count)
            for i in 0..<count {
                samples[warmup + i] = ch0[i] * 0.82
            }

            let engine = VoiceStudioEngine()
            var demoProfile = VoiceProfile.studioCrispAndDeep
            demoProfile.pitchCents = -75
            demoProfile.subWarmth = 0.30
            demoProfile.chestWarmthDb = 4.2
            demoProfile.mudCutDb = 3.0
            demoProfile.presenceDb = 4.2
            demoProfile.airDb = 5.0
            demoProfile.compressionAmount = 0.62
            demoProfile.outputGainDb = 2.0
            engine.applyProfile(demoProfile)

            let rendered = engine.renderBufferOfflineForTesting(samples)
            let trimmed = Array(rendered.dropFirst(warmup))

            let outURL = URL(fileURLWithPath: studioOutPath)
            try? FileManager.default.removeItem(at: outURL)
            let outFile = try AVAudioFile(forWriting: outURL, settings: format.settings)
            guard let outPCM = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(trimmed.count)) else { return }
            outPCM.frameLength = AVAudioFrameCount(trimmed.count)
            if let outCh = outPCM.floatChannelData?[0] {
                for i in 0..<trimmed.count {
                    outCh[i] = trimmed[i]
                }
            }
            try outFile.write(from: outPCM)
            print("Processed \(trimmed.count) frames -> Raw: \(rawOutPath), Studio: \(studioOutPath)")
        } catch {
            fputs("WAV DSP processing failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func renderExactCanvasView<Content: View>(
        size: CGSize,
        to path: String,
        @ViewBuilder content: () -> Content
    ) {
        let root = content()
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = NSRect(origin: .zero, size: size)
        window.contentView = hostingView

        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.10))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }
        rep.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
        window.orderOut(nil)
    }

    private static func renderFramedScreenshot<Content: View>(
        title: String,
        showTrafficLights: Bool,
        contentSize: CGSize,
        to path: String,
        @ViewBuilder content: () -> Content
    ) {
        let margin: CGFloat = 28
        let titleBarH: CGFloat = 32
        let totalSize = CGSize(
            width: contentSize.width + margin * 2,
            height: contentSize.height + titleBarH + margin * 2
        )

        let framedView = ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.045, blue: 0.075),
                    Color(red: 0.08, green: 0.11, blue: 0.18),
                    Color(red: 0.04, green: 0.06, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                // Simulated native macOS dark window bar
                HStack(spacing: 8) {
                    if showTrafficLights {
                        Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                        Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                        Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "waveform.badge.mic")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(StudioTheme.accentCyan)
                    }
                    Spacer()
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer()
                    if showTrafficLights {
                        Color.clear.frame(width: 52, height: 12)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: titleBarH)
                .background(Color(red: 0.08, green: 0.095, blue: 0.13))

                Divider().overlay(Color.white.opacity(0.08))

                content()
                    .frame(width: contentSize.width, height: contentSize.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 20, x: 0, y: 10)
            .padding(margin)
        }
        .frame(width: totalSize.width, height: totalSize.height)
        .environment(\.colorScheme, .dark)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: totalSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        let hostingView = NSHostingView(rootView: framedView)
        hostingView.frame = NSRect(origin: .zero, size: totalSize)
        window.contentView = hostingView

        // Pump RunLoop briefly so AppKit NSPopUpButton/NSSlider/Canvas complete layout
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.10))

        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
        window.orderOut(nil)
    }
}

private struct SocialPreviewCardView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.055, blue: 0.095),
                    Color(red: 0.08, green: 0.11, blue: 0.19),
                    Color(red: 0.045, green: 0.065, blue: 0.11)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(spacing: 38) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Circle().fill(StudioTheme.accentEmerald).frame(width: 10, height: 10)
                            Text("OPEN SOURCE • 0.4% CPU")
                                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                .foregroundStyle(StudioTheme.accentEmerald)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(StudioTheme.accentEmerald.opacity(0.16))
                        .clipShape(Capsule())

                        Text("macOS 13+ Universal")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(StudioTheme.accentCyan)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(StudioTheme.accentCyan.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("VoiceStudio")
                            .font(.system(size: 64, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Real-Time Broadcast Voice Rack for macOS")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(StudioTheme.accentCyan)
                    }

                    Text("Turn any USB or built-in mic into a crisp, warm, subtly deeper studio voice across Discord, Zoom, Teams, Slack, Meet & OBS.")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Image(systemName: "terminal.fill")
                            .foregroundStyle(StudioTheme.accentAmber)
                        Text("brew install --cask saadmsft/tap/voicestudio")
                            .font(.system(size: 15.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(StudioTheme.accentAmber.opacity(0.5), lineWidth: 1.2)
                    )

                    HStack(spacing: 12) {
                        ForEach(["Discord", "Zoom", "Teams", "Slack", "Google Meet", "OBS Studio"], id: \.self) { app in
                            Text(app)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white.opacity(0.88))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 14) {
                    EQCurveVisualizer(profile: .studioCrispAndDeep, isBypassed: false)
                        .frame(width: 410)

                    HStack(spacing: 12) {
                        statCard(title: "PITCH DEPTH", value: "-0.65 st", accent: StudioTheme.accentAmber)
                        statCard(title: "SUB WARMTH", value: "24% Tube", accent: StudioTheme.accentAmber)
                        statCard(title: "STUDIO AIR", value: "+4.5 dB", accent: StudioTheme.accentCyan)
                    }
                    .frame(width: 410)
                }
            }
            .padding(54)
        }
    }

    private func statCard(title: String, value: String, accent: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .monospaced))
                .foregroundStyle(accent)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(StudioTheme.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(accent.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct DemoVideoFrameView: View {
    let badgeText: String
    let badgeColor: Color
    let subtitle: String
    @ObservedObject var vm: StudioViewModel

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.045, blue: 0.075)

            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Text(badgeText)
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(badgeColor)
                        .clipShape(Capsule())

                    Text(subtitle)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))

                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)

                MainStudioView(vm: vm)
                    .frame(width: 1224, height: 632)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(badgeColor.opacity(0.55), lineWidth: 2)
                    )
            }
        }
    }
}
