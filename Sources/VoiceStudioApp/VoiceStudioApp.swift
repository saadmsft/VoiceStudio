import AppKit
import SwiftUI

struct StudioWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(red: 0.055, green: 0.065, blue: 0.090, alpha: 1.0)
            window.isMovableByWindowBackground = false
            window.titlebarAppearsTransparent = false
            window.styleMask.remove(.fullSizeContentView)
            window.minSize = NSSize(width: 920, height: 660)

            // Ensure any cramped cached frame from earlier runs expands cleanly
            var frame = window.frame
            if frame.height < 800 || frame.width < 960 {
                let targetW = max(frame.width, 980)
                let targetH = max(frame.height, 820)
                frame.origin.y -= (targetH - frame.height) * 0.5
                frame.origin.x -= (targetW - frame.width) * 0.5
                frame.size = NSSize(width: targetW, height: targetH)
                if let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
                    frame.origin.x = max(visible.minX + 16, min(frame.origin.x, visible.maxX - frame.width - 16))
                    frame.origin.y = max(visible.minY + 16, min(frame.origin.y, visible.maxY - frame.height - 16))
                }
                window.setFrame(frame, display: true, animate: false)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

@main
struct VoiceStudioApp: App {
    @StateObject private var viewModel = StudioViewModel()

    init() {
        if ScreenshotExporter.runIfRequested() {
            exit(0)
        }
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("VoiceStudio — Teams Broadcast Rack", id: "studio-main") {
            MainStudioView(vm: viewModel)
                .background(StudioWindowConfigurator())
        }
        .defaultSize(width: 980, height: 810)

        MenuBarExtra {
            MenuBarPopoverView(vm: viewModel)
        } label: {
            Image(systemName: viewModel.isMuted
                  ? "mic.slash.fill"
                  : (viewModel.isEngineRunning ? "waveform.badge.mic" : "mic"))
        }
        .menuBarExtraStyle(.window)
    }
}
