import AppKit
import SwiftUI
import VoiceStudioCore

struct MenuBarPopoverView: View {
    @ObservedObject var vm: StudioViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(vm.isEngineRunning ? StudioTheme.accentEmerald : .gray)
                    .frame(width: 8, height: 8)
                Text("VoiceStudio")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button(vm.isEngineRunning ? "Stop" : "Start") {
                    vm.toggleEngine()
                }
                .controlSize(.small)
            }

            HStack(spacing: 6) {
                Button {
                    vm.isMuted.toggle()
                } label: {
                    Label(vm.isMuted ? "Muted" : "Mute", systemImage: vm.isMuted ? "mic.slash.fill" : "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(vm.isMuted ? .red : nil)

                Button {
                    vm.isBypassed.toggle()
                } label: {
                    Label(vm.isBypassed ? "Bypassed" : "FX On", systemImage: "waveform")
                        .frame(maxWidth: .infinity)
                }
            }
            .controlSize(.small)

            Picker("Preset", selection: Binding(
                get: { vm.profile.id },
                set: { id in
                    if let p = vm.allPresets.first(where: { $0.id == id }) {
                        vm.selectPreset(p)
                    }
                }
            )) {
                ForEach(vm.allPresets) { p in
                    Text(p.name).tag(p.id)
                }
            }
            .controlSize(.small)

            Divider()

            VStack(spacing: 8) {
                quickSlider("Depth", value: $vm.profile.pitchCents, range: -250...150, text: vm.profile.semitonesFormatted)
                quickSlider("Warmth", value: $vm.profile.chestWarmthDb, range: -3...9, text: String(format: "%+.1f dB", vm.profile.chestWarmthDb))
                quickSlider("Crisp", value: $vm.profile.presenceDb, range: -3...9, text: String(format: "%+.1f dB", vm.profile.presenceDb))
                quickSlider("Air", value: $vm.profile.airDb, range: -3...10, text: String(format: "%+.1f dB", vm.profile.airDb))
            }

            Divider()

            HStack {
                Button("Open Full Studio Rack") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "studio-main")
                }
                .controlSize(.small)

                Spacer()

                Button("Quit") {
                    vm.stopEngine()
                    NSApp.terminate(nil)
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 290)
    }

    private func quickSlider(_ label: String, value: Binding<Float>, range: ClosedRange<Float>, text: String) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(text)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .controlSize(.mini)
        }
    }
}
