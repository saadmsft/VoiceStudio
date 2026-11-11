import SwiftUI

struct VoiceCheckBar: View {
    @ObservedObject var vm: StudioViewModel

    var body: some View {
        HStack(spacing: 14) {
            // LEFT: Feedback-Free 5s Record & Live-Loop Tweak
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform.circle.fill")
                            .foregroundStyle(StudioTheme.accentAmber)
                        Text("Feedback-Free Voice Check")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text(voiceCheckSubtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer(minLength: 4)

                // Record 5s button
                Button {
                    vm.toggleVoiceCheckRecording()
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(vm.isRecordingCheck ? .white : StudioTheme.accentCoral)
                            .frame(width: 8, height: 8)
                        Text(vm.isRecordingCheck
                             ? String(format: "Stop (%.1fs)", vm.checkRecordingProgress * 6.0)
                             : "Record 5s")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(vm.isRecordingCheck ? StudioTheme.accentCoral : Color.white.opacity(0.09))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)

                // Loop & Tweak button
                Button {
                    vm.toggleVoiceCheckLoop()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: vm.isPlayingCheckLoop ? "stop.fill" : "repeat")
                            .font(.system(size: 10.5, weight: .bold))
                        Text(vm.isPlayingCheckLoop ? "Stop Loop" : "Loop & Tweak")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(vm.isPlayingCheckLoop ? StudioTheme.accentCyan.opacity(0.26) : Color.white.opacity(0.08))
                    .foregroundStyle(vm.isPlayingCheckLoop ? StudioTheme.accentCyan : .white.opacity(vm.hasRecordedCheck ? 0.9 : 0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!vm.hasRecordedCheck)

                // Instant A/B Toggle while looping
                if vm.hasRecordedCheck {
                    Button {
                        vm.checkCompareRawOriginal.toggle()
                    } label: {
                        Text(vm.checkCompareRawOriginal ? "Hearing: RAW MIC" : "Hearing: STUDIO FX")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(vm.checkCompareRawOriginal ? Color.gray.opacity(0.28) : StudioTheme.accentEmerald.opacity(0.22))
                            .foregroundStyle(vm.checkCompareRawOriginal ? .white : StudioTheme.accentEmerald)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Compare your raw microphone vs modified studio voice")
                }
            }
            .padding(10)
            .background(StudioTheme.panelBg)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(vm.isPlayingCheckLoop ? StudioTheme.accentCyan.opacity(0.5) : StudioTheme.border, lineWidth: 1)
            )

            // RIGHT: Live Headphone Monitor ("Hear Myself")
            HStack(spacing: 10) {
                Button {
                    vm.liveMonitorEnabled.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: vm.liveMonitorEnabled ? "headphones.circle.fill" : "headphones")
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Hear Myself Live")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text(vm.liveMonitorEnabled ? "On (Use Headphones)" : "Off")
                                .font(.system(size: 9.5))
                                .opacity(0.75)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(vm.liveMonitorEnabled ? StudioTheme.accentAmber.opacity(0.22) : Color.white.opacity(0.07))
                    .foregroundStyle(vm.liveMonitorEnabled ? StudioTheme.accentAmber : .white.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Monitor Vol \(Int(vm.monitorVolume * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                    Slider(value: $vm.monitorVolume, in: 0...1.0)
                        .tint(StudioTheme.accentAmber)
                        .controlSize(.mini)
                        .frame(width: 90)
                }
            }
            .padding(10)
            .background(StudioTheme.panelBg)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )
        }
    }

    private var voiceCheckSubtitle: String {
        if vm.isRecordingCheck {
            return "Speak normally for a few seconds…"
        }
        if vm.isPlayingCheckLoop {
            return "Playing on speakers (Virtual Mic muted) — drag sliders above to tweak live!"
        }
        return "Record once & loop on speakers to dial in sliders with zero feedback"
    }
}
