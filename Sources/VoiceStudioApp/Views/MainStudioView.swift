import AppKit
import CoreAudio
import SwiftUI
import VoiceStudioCore

struct MainStudioView: View {
    @ObservedObject var vm: StudioViewModel
    @State private var showingSavePresetPopover = false
    @State private var newPresetName = ""

    var body: some View {
        VStack(spacing: 12) {
            headerBar
            if let err = vm.errorBanner {
                permissionOrErrorBanner(err)
            }
            routingAndPresetsSection

            ScrollView(.vertical, showsIndicators: true) {
                centerStudioRack
                    .padding(.vertical, 2)
                    .padding(.trailing, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VoiceCheckBar(vm: vm)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 14)
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .frame(minWidth: 900, minHeight: 620)
        .background(StudioTheme.bgDeep)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $vm.showTeamsGuide) {
            TeamsSetupSheet(vm: vm)
        }
    }

    // MARK: - Top Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            // Brand + On-Air Toggle
            Button {
                vm.toggleEngine()
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(vm.isEngineRunning ? StudioTheme.accentEmerald : Color.gray)
                        .frame(width: 9, height: 9)
                        .shadow(color: vm.isEngineRunning ? StudioTheme.accentEmerald.opacity(0.8) : .clear, radius: 5)
                    Text(vm.isEngineRunning ? "ON AIR" : "STANDBY")
                        .font(.system(size: 11.5, weight: .heavy, design: .monospaced))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(vm.isEngineRunning ? StudioTheme.accentEmerald.opacity(0.16) : Color.white.opacity(0.07))
                .foregroundStyle(vm.isEngineRunning ? StudioTheme.accentEmerald : .white.opacity(0.7))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text("VoiceStudio for Microsoft Teams")
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(vm.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(vm.isBlackHoleSelected && vm.isEngineRunning ? StudioTheme.accentEmerald : .white.opacity(0.55))
            }

            Spacer()

            // Mute button
            Button {
                vm.isMuted.toggle()
            } label: {
                Label(vm.isMuted ? "MUTED" : "Mute Mic", systemImage: vm.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(vm.isMuted ? StudioTheme.accentCoral : Color.white.opacity(0.08))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            // Bypass button
            Button {
                vm.isBypassed.toggle()
            } label: {
                Label(vm.isBypassed ? "FX Bypassed" : "Bypass FX", systemImage: "waveform.slash")
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(vm.isBypassed ? StudioTheme.accentAmber.opacity(0.28) : Color.white.opacity(0.08))
                    .foregroundStyle(vm.isBypassed ? StudioTheme.accentAmber : .white.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            // Teams Setup Guide button
            Button {
                vm.showTeamsGuide = true
            } label: {
                Label("Teams Setup", systemImage: "questionmark.circle")
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(StudioTheme.accentCyan.opacity(0.14))
                    .foregroundStyle(StudioTheme.accentCyan)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func permissionOrErrorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(StudioTheme.accentAmber)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            if vm.micPermissionDenied {
                Button("Open Privacy Settings") {
                    vm.openSystemMicrophonePrivacy()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Button("Retry") {
                vm.checkMicrophonePermissionAndAutostart()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(StudioTheme.accentCoral.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Device Routing & Presets Strip

    private var routingAndPresetsSection: some View {
        VStack(spacing: 10) {
            // Audio I/O Bar
            HStack(spacing: 12) {
                devicePickerBox(
                    icon: "mic.fill",
                    label: "MICROPHONE INPUT",
                    selection: Binding(
                        get: { vm.selectedInputID },
                        set: { vm.userChangedInputDevice($0) }
                    ),
                    devices: vm.inputDevices
                )

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))

                devicePickerBox(
                    icon: "cable.connector",
                    label: "TEAMS VIRTUAL MIC OUTPUT",
                    selection: Binding(
                        get: { vm.selectedOutputID },
                        set: { vm.userChangedOutputDevice($0) }
                    ),
                    devices: vm.outputDevices
                )

                Image(systemName: "headphones")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))

                devicePickerBox(
                    icon: "speaker.wave.2.fill",
                    label: "MONITOR / VOICE CHECK SPEAKER",
                    selection: Binding(
                        get: { vm.selectedMonitorID },
                        set: { vm.userChangedMonitorDevice($0) }
                    ),
                    devices: vm.monitorDevices
                )
            }

            // Preset Strip
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(vm.allPresets) { preset in
                            let selected = vm.profile.id == preset.id
                            HStack(spacing: 5) {
                                Button {
                                    vm.selectPreset(preset)
                                } label: {
                                    Text(preset.name)
                                        .font(.system(size: 11.5, weight: selected ? .bold : .medium))
                                }
                                .buttonStyle(.plain)

                                if !preset.isBuiltIn {
                                    Button {
                                        vm.deleteCustomPreset(preset)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 10.5))
                                            .opacity(0.7)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Delete custom preset")
                                }
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(selected ? StudioTheme.accentCyan.opacity(0.24) : StudioTheme.panelBg)
                            .foregroundStyle(selected ? StudioTheme.accentCyan : .white.opacity(0.8))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(selected ? StudioTheme.accentCyan.opacity(0.7) : StudioTheme.border, lineWidth: 1)
                            )
                        }
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 2)
                }

                Button {
                    vm.resetToCurrentPresetDefault()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    newPresetName = ""
                    showingSavePresetPopover = true
                } label: {
                    Label("Save Preset", systemImage: "plus.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(StudioTheme.accentAmber.opacity(0.18))
                        .foregroundStyle(StudioTheme.accentAmber)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingSavePresetPopover) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Save Custom Voice Preset")
                            .font(.system(size: 12.5, weight: .bold))
                        TextField("e.g. Morning Standup", text: $newPresetName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                        HStack {
                            Spacer()
                            Button("Save") {
                                vm.saveCustomPreset(named: newPresetName)
                                showingSavePresetPopover = false
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func devicePickerBox(
        icon: String,
        label: String,
        selection: Binding<AudioDeviceID>,
        devices: [AudioDeviceInfo]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            Picker("", selection: selection) {
                ForEach(devices) { dev in
                    Text(dev.name).tag(dev.id)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(StudioTheme.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Center Broadcast Rack (EQ Curve + Sliders + Live Meters)

    private var centerStudioRack: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 10) {
                EQCurveVisualizer(profile: vm.profile, isBypassed: vm.isBypassed)

                HStack(alignment: .top, spacing: 12) {
                    depthAndWarmthModule
                    crispnessAndDynamicsModule
                }
            }

            liveMeterBridge
        }
    }

    private var depthAndWarmthModule: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform.and.magnifyingglass")
                    .foregroundStyle(StudioTheme.accentAmber)
                Text("DEPTH & BROADCAST WARMTH")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.accentAmber)
                Spacer()
            }

            StudioSliderRow(
                title: "Voice Depth (Pitch)",
                hint: "-0.5 to -1.0 st = natural depth",
                value: $vm.profile.pitchCents,
                range: -250...150,
                defaultValue: -65,
                accent: StudioTheme.accentAmber,
                formatter: { String(format: "%+.2f st", $0 / 100.0) }
            )

            StudioSliderRow(
                title: "Sub-Harmonic Body",
                hint: "Chest octave resonance & tube warmth",
                value: $vm.profile.subWarmth,
                range: 0...1.0,
                defaultValue: 0.24,
                accent: StudioTheme.accentAmber,
                formatter: { "\(Int($0 * 100))%" }
            )

            StudioSliderRow(
                title: "Chest Warmth (125 Hz)",
                hint: "Close-mic podcast fullness",
                value: $vm.profile.chestWarmthDb,
                range: -3...9,
                defaultValue: 3.5,
                accent: StudioTheme.accentAmber,
                formatter: { String(format: "%+.1f dB", $0) }
            )

            StudioSliderRow(
                title: "Mud Cleanup (310 Hz)",
                hint: "Cuts boxy room resonance",
                value: $vm.profile.mudCutDb,
                range: 0...6,
                defaultValue: 2.5,
                accent: StudioTheme.accentCyan,
                formatter: { String(format: "-%.1f dB", $0) }
            )

            StudioSliderRow(
                title: "Rumble Cut (Low-Cut)",
                hint: "Removes desk bumps & AC hum",
                value: $vm.profile.lowCutHz,
                range: 40...140,
                defaultValue: 80,
                accent: StudioTheme.accentCyan,
                formatter: { "\(Int($0)) Hz" }
            )

            StudioSliderRow(
                title: "Mic Input Pre-Gain",
                hint: "Boost quiet USB or dynamic mics",
                value: $vm.profile.inputGainDb,
                range: -12...18,
                defaultValue: 0.0,
                accent: StudioTheme.accentEmerald,
                formatter: { String(format: "%+.1f dB", $0) }
            )
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(StudioTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private var crispnessAndDynamicsModule: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(StudioTheme.accentCyan)
                Text("CRISPNESS & STUDIO DYNAMICS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.accentCyan)
                Spacer()
            }

            StudioSliderRow(
                title: "Vocal Crispness (4.2 kHz)",
                hint: "Clarity & consonant definition",
                value: $vm.profile.presenceDb,
                range: -3...9,
                defaultValue: 3.8,
                accent: StudioTheme.accentCyan,
                formatter: { String(format: "%+.1f dB", $0) }
            )

            StudioSliderRow(
                title: "Condenser Air (9.5 kHz)",
                hint: "Crisp studio high-shelf sheen",
                value: $vm.profile.airDb,
                range: -3...10,
                defaultValue: 4.5,
                accent: StudioTheme.accentCyan,
                formatter: { String(format: "%+.1f dB", $0) }
            )

            StudioSliderRow(
                title: "De-Esser Smoothness",
                hint: "Tames sharp 'S' & 'SH' sounds",
                value: $vm.profile.deEsserAmount,
                range: 0...1.0,
                defaultValue: 0.35,
                accent: StudioTheme.accentEmerald,
                formatter: { "\(Int($0 * 100))%" }
            )

            StudioSliderRow(
                title: "Studio Compressor",
                hint: "Consistent upfront broadcast level",
                value: $vm.profile.compressionAmount,
                range: 0...1.0,
                defaultValue: 0.55,
                accent: StudioTheme.accentEmerald,
                formatter: { "\(Int($0 * 100))%" }
            )

            HStack(spacing: 10) {
                Toggle(isOn: $vm.profile.gateEnabled) {
                    Text("Noise Gate")
                        .font(.system(size: 12, weight: .semibold))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                Slider(value: $vm.profile.gateThresholdDb, in: -75...(-25))
                    .tint(StudioTheme.accentEmerald)
                    .controlSize(.small)
                    .disabled(!vm.profile.gateEnabled)

                Text("\(Int(vm.profile.gateThresholdDb)) dB")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(vm.profile.gateEnabled ? StudioTheme.accentEmerald : .gray)
                    .frame(width: 48, alignment: .trailing)
            }

            StudioSliderRow(
                title: "Studio Output Trim",
                hint: "Brickwall soft-limited @ -0.7 dBFS",
                value: $vm.profile.outputGainDb,
                range: -10...10,
                defaultValue: 1.5,
                accent: StudioTheme.accentEmerald,
                formatter: { String(format: "%+.1f dB", $0) }
            )
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(StudioTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private var liveMeterBridge: some View {
        LiveMeterBridgeView(meters: vm.meters)
    }
}

private struct LiveMeterBridgeView: View {
    @ObservedObject var meters: MeterTelemetry

    var body: some View {
        VStack(spacing: 8) {
            Text("METERS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 10) {
                VerticalLEDMeter(label: "IN", dbValue: meters.inputMeterDb, isGainReduction: false)
                VerticalLEDMeter(label: "GR", dbValue: meters.gainReductionDb, isGainReduction: true)
                VerticalLEDMeter(label: "OUT", dbValue: meters.outputMeterDb, isGainReduction: false)
            }
            .frame(height: 365)

            Text(meters.outputMeterDb > -80 ? String(format: "%.0f dB", meters.outputMeterDb) : "-∞ dB")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(StudioTheme.accentEmerald)
        }
        .padding(12)
        .frame(width: 96)
        .background(StudioTheme.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }
}
