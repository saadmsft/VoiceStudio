import AppKit
import SwiftUI
import VoiceStudioCore

@MainActor
enum ScreenshotExporter {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--export-screenshots"), idx + 1 < args.count else {
            return false
        }
        let outDir = args[idx + 1]
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        // 1. Main Studio Console ("Teams Crisp & Deep")
        let vm1 = StudioViewModel(screenshotPreviewMode: true)
        renderFramedScreenshot(
            title: "VoiceStudio — Teams Broadcast Rack",
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

        print("Exported screenshots to \(outDir)")
        return true
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
