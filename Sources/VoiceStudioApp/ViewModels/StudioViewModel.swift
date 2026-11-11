import AVFoundation
import AppKit
import Combine
import CoreAudio
import Foundation
import VoiceStudioCore

@MainActor
public final class MeterTelemetry: ObservableObject {
    @Published public var inputMeterDb: Float = -90.0
    @Published public var outputMeterDb: Float = -90.0
    @Published public var gainReductionDb: Float = 0.0

    public init() {}
}

@MainActor
public final class StudioViewModel: ObservableObject {
    // Isolated meter observable so MenuBarExtra & Sliders never re-render on 20fps meter ticks
    public let meters = MeterTelemetry()
    // Devices
    @Published public var inputDevices: [AudioDeviceInfo] = []
    @Published public var outputDevices: [AudioDeviceInfo] = []
    @Published public var monitorDevices: [AudioDeviceInfo] = []

    @Published public var selectedInputID: AudioDeviceID = 0
    @Published public var selectedOutputID: AudioDeviceID = 0
    @Published public var selectedMonitorID: AudioDeviceID = 0

    // Engine & Controls
    @Published public var isEngineRunning: Bool = false
    @Published public var isMuted: Bool = false {
        didSet { engine.isMuted = isMuted }
    }
    @Published public var isBypassed: Bool = false {
        didSet { engine.isBypassed = isBypassed }
    }
    @Published public var liveMonitorEnabled: Bool = false {
        didSet {
            engine.setLiveMonitor(enabled: liveMonitorEnabled, monitorDeviceID: selectedMonitorID)
        }
    }
    @Published public var monitorVolume: Float = 0.85 {
        didSet { engine.monitorVolume = monitorVolume }
    }

    // Voice Check (5s Record & Live-Loop Tweak)
    @Published public var isRecordingCheck: Bool = false
    @Published public var isPlayingCheckLoop: Bool = false
    @Published public var hasRecordedCheck: Bool = false
    @Published public var checkRecordingProgress: Double = 0.0
    @Published public var checkCompareRawOriginal: Bool = false {
        didSet { engine.checkCompareRawOriginal = checkCompareRawOriginal }
    }

    // Profiles & Presets
    @Published public var profile: VoiceProfile = .studioCrispAndDeep {
        didSet {
            engine.applyProfile(profile)
            persistCurrentProfile()
        }
    }
    @Published public var customPresets: [VoiceProfile] = []

    // Permissions & Status
    @Published public var micPermissionGranted: Bool = false
    @Published public var micPermissionDenied: Bool = false
    @Published public var statusMessage: String = "Initializing audio studio…"
    @Published public var errorBanner: String? = nil
    @Published public var showAppSetupGuide: Bool = false

    private let engine = VoiceStudioEngine()
    private let deviceManager = CoreAudioDeviceManager.shared
    private var meterTimer: Timer?

    private let profileStorageKey = "VoiceStudio.ActiveProfile.v1"
    private let customPresetsKey = "VoiceStudio.CustomPresets.v1"
    private let inputUIDKey = "VoiceStudio.SelectedInputUID.v1"
    private let outputUIDKey = "VoiceStudio.SelectedOutputUID.v1"
    private let monitorUIDKey = "VoiceStudio.SelectedMonitorUID.v1"

    private var isPreviewInstance: Bool = false

    public init(screenshotPreviewMode: Bool = false) {
        self.isPreviewInstance = screenshotPreviewMode
        if screenshotPreviewMode {
            inputDevices = [
                AudioDeviceInfo(id: 101, uid: "usb-mic", name: "USB Studio Condenser Mic", manufacturer: "Audio", inputChannels: 2, outputChannels: 0, sampleRate: 48000, isVirtual: false),
                AudioDeviceInfo(id: 102, uid: "mbp-mic", name: "MacBook Pro Microphone", manufacturer: "Apple", inputChannels: 1, outputChannels: 0, sampleRate: 48000, isVirtual: false)
            ]
            outputDevices = [
                AudioDeviceInfo(id: 201, uid: "BlackHole2ch_UID", name: "BlackHole 2ch", manufacturer: "Existential Audio", inputChannels: 2, outputChannels: 2, sampleRate: 48000, isVirtual: true)
            ]
            monitorDevices = [
                AudioDeviceInfo(id: 301, uid: "studio-hp", name: "Studio Headphones", manufacturer: "Apple", inputChannels: 0, outputChannels: 2, sampleRate: 48000, isVirtual: false),
                AudioDeviceInfo(id: 302, uid: "mbp-spk", name: "MacBook Pro Speakers", manufacturer: "Apple", inputChannels: 0, outputChannels: 2, sampleRate: 48000, isVirtual: false)
            ]
            selectedInputID = 101
            selectedOutputID = 201
            selectedMonitorID = 301
            isEngineRunning = true
            micPermissionGranted = true
            statusMessage = "ON AIR • Routing to BlackHole 2ch (Discord • Zoom • Teams • OBS)"
            profile = .studioCrispAndDeep
            meters.inputMeterDb = -13.5
            meters.gainReductionDb = 4.2
            meters.outputMeterDb = -6.8
            return
        }

        loadSavedPresetsAndProfile()
        refreshDevices(preserveSelections: false)

        deviceManager.onDevicesChanged = { [weak self] in
            Task { @MainActor in
                self?.refreshDevices(preserveSelections: true)
            }
        }

        startMeterPolling()
        checkMicrophonePermissionAndAutostart()
    }

    public var allPresets: [VoiceProfile] {
        VoiceProfile.builtInPresets + customPresets
    }

    public var isBlackHoleSelected: Bool {
        guard let out = outputDevices.first(where: { $0.id == selectedOutputID }) else { return false }
        return out.isBlackHole
    }

    public var selectedOutputName: String {
        outputDevices.first(where: { $0.id == selectedOutputID })?.name ?? "None"
    }

    public var selectedInputName: String {
        inputDevices.first(where: { $0.id == selectedInputID })?.name ?? "None"
    }

    // MARK: - Permissions & Lifecycle

    public func checkMicrophonePermissionAndAutostart() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            micPermissionGranted = true
            micPermissionDenied = false
            startEngine()
        case .notDetermined:
            statusMessage = "Requesting microphone access…"
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    self.micPermissionGranted = granted
                    self.micPermissionDenied = !granted
                    if granted {
                        self.startEngine()
                    } else {
                        self.statusMessage = "Microphone permission required"
                        self.errorBanner = "Grant Microphone access in System Settings → Privacy & Security → Microphone."
                    }
                }
            }
        case .denied, .restricted:
            micPermissionGranted = false
            micPermissionDenied = true
            statusMessage = "Microphone access denied"
            errorBanner = "Enable VoiceStudio in System Settings → Privacy & Security → Microphone."
        @unknown default:
            break
        }
    }

    public func openSystemMicrophonePrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Device Management

    public func refreshDevices(preserveSelections: Bool) {
        let newInputs = deviceManager.inputDevices()
        let newOutputs = deviceManager.outputDevices()
        let newMonitors = deviceManager.monitorDevices()

        inputDevices = newInputs
        outputDevices = newOutputs
        monitorDevices = newMonitors

        let savedInUID = UserDefaults.standard.string(forKey: inputUIDKey)
        let savedOutUID = UserDefaults.standard.string(forKey: outputUIDKey)
        let savedMonUID = UserDefaults.standard.string(forKey: monitorUIDKey)

        if preserveSelections, newInputs.contains(where: { $0.id == selectedInputID }) {
            // keep current
        } else if let uid = savedInUID, let match = newInputs.first(where: { $0.uid == uid }) {
            selectedInputID = match.id
        } else if let pref = deviceManager.preferredInputDevice() {
            selectedInputID = pref.id
        }

        if preserveSelections, newOutputs.contains(where: { $0.id == selectedOutputID }) {
            // keep current
        } else if let uid = savedOutUID, let match = newOutputs.first(where: { $0.uid == uid }) {
            selectedOutputID = match.id
        } else if let pref = deviceManager.preferredVirtualMicOutput() {
            selectedOutputID = pref.id
        }

        if preserveSelections, newMonitors.contains(where: { $0.id == selectedMonitorID }) {
            // keep current
        } else if let uid = savedMonUID, let match = newMonitors.first(where: { $0.uid == uid }) {
            selectedMonitorID = match.id
        } else if let pref = deviceManager.preferredMonitorOutput() {
            selectedMonitorID = pref.id
        }
    }

    public func userChangedInputDevice(_ id: AudioDeviceID) {
        selectedInputID = id
        if let uid = inputDevices.first(where: { $0.id == id })?.uid {
            UserDefaults.standard.set(uid, forKey: inputUIDKey)
        }
        if isEngineRunning { startEngine() }
    }

    public func userChangedOutputDevice(_ id: AudioDeviceID) {
        selectedOutputID = id
        if let uid = outputDevices.first(where: { $0.id == id })?.uid {
            UserDefaults.standard.set(uid, forKey: outputUIDKey)
        }
        if isEngineRunning { startEngine() }
    }

    public func userChangedMonitorDevice(_ id: AudioDeviceID) {
        selectedMonitorID = id
        if let uid = monitorDevices.first(where: { $0.id == id })?.uid {
            UserDefaults.standard.set(uid, forKey: monitorUIDKey)
        }
        engine.setLiveMonitor(enabled: liveMonitorEnabled, monitorDeviceID: id)
    }

    // MARK: - Engine Control

    public func toggleEngine() {
        if isEngineRunning {
            stopEngine()
        } else {
            startEngine()
        }
    }

    public func startEngine() {
        guard selectedInputID != 0, selectedOutputID != 0 else {
            errorBanner = "Select valid input microphone and output device."
            return
        }

        do {
            engine.applyProfile(profile)
            try engine.start(
                inputDeviceID: selectedInputID,
                outputDeviceID: selectedOutputID,
                monitorDeviceID: selectedMonitorID != 0 ? selectedMonitorID : nil,
                enableLiveMonitor: liveMonitorEnabled
            )
            isEngineRunning = true
            errorBanner = nil
            statusMessage = isBlackHoleSelected
                ? "ON AIR • Routing to BlackHole 2ch (Discord • Zoom • Teams • OBS)"
                : "ON AIR • Routing to \(selectedOutputName)"
        } catch {
            isEngineRunning = false
            errorBanner = error.localizedDescription
            statusMessage = "Audio engine stopped"
        }
    }

    public func stopEngine() {
        if isPlayingCheckLoop {
            engine.setVoiceCheckLoopPlayback(playing: false, monitorDeviceID: nil)
            isPlayingCheckLoop = false
        }
        isRecordingCheck = false
        engine.stop()
        isEngineRunning = false
        statusMessage = "Standby"
        meters.inputMeterDb = -90.0
        meters.outputMeterDb = -90.0
        meters.gainReductionDb = 0.0
    }

    // MARK: - 5-Second Record & Live-Loop Tweak

    public func toggleVoiceCheckRecording() {
        if !isEngineRunning {
            startEngine()
        }
        guard isEngineRunning else { return }

        if engine.isRecordingVoiceCheck {
            _ = engine.stopVoiceCheckRecording()
            isRecordingCheck = false
            hasRecordedCheck = engine.hasRecordedVoiceCheck
            if hasRecordedCheck {
                startLoopPlayback()
            }
        } else {
            isPlayingCheckLoop = false
            engine.setVoiceCheckLoopPlayback(playing: false, monitorDeviceID: selectedMonitorID)
            engine.startVoiceCheckRecording()
            isRecordingCheck = true
        }
    }

    public func toggleVoiceCheckLoop() {
        if isPlayingCheckLoop {
            stopLoopPlayback()
        } else {
            startLoopPlayback()
        }
    }

    private func startLoopPlayback() {
        guard engine.hasRecordedVoiceCheck else { return }
        if !isEngineRunning { startEngine() }
        engine.setVoiceCheckLoopPlayback(playing: true, monitorDeviceID: selectedMonitorID)
        isPlayingCheckLoop = true
    }

    public func stopLoopPlayback() {
        engine.setVoiceCheckLoopPlayback(playing: false, monitorDeviceID: selectedMonitorID)
        isPlayingCheckLoop = false
    }

    // MARK: - Presets & Persistence

    public func selectPreset(_ preset: VoiceProfile) {
        profile = preset
    }

    public func resetToCurrentPresetDefault() {
        if let builtIn = VoiceProfile.builtInPresets.first(where: { $0.id == profile.id }) {
            profile = builtIn
        } else {
            profile = .studioCrispAndDeep
        }
    }

    public func saveCustomPreset(named rawName: String) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var newPreset = profile
        newPreset.id = "custom-\(UUID().uuidString)"
        newPreset.name = trimmed
        newPreset.subtitle = "Saved Custom Voice"
        newPreset.isBuiltIn = false
        customPresets.append(newPreset)
        profile = newPreset
        persistCustomPresets()
    }

    public func deleteCustomPreset(_ preset: VoiceProfile) {
        guard !preset.isBuiltIn else { return }
        customPresets.removeAll { $0.id == preset.id }
        persistCustomPresets()
        if profile.id == preset.id {
            profile = .studioCrispAndDeep
        }
    }

    private func loadSavedPresetsAndProfile() {
        if let data = UserDefaults.standard.data(forKey: customPresetsKey),
           let decoded = try? JSONDecoder().decode([VoiceProfile].self, from: data) {
            customPresets = decoded
        }
        if let data = UserDefaults.standard.data(forKey: profileStorageKey),
           var saved = try? JSONDecoder().decode(VoiceProfile.self, from: data) {
            if saved.id == "builtin-teams-crisp-deep" {
                saved.id = "builtin-studio-crisp-deep"
                saved.name = "Studio Crisp & Deep"
            }
            profile = saved
        }
    }

    private func persistCurrentProfile() {
        guard !isPreviewInstance else { return }
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profileStorageKey)
        }
    }

    private func persistCustomPresets() {
        if let data = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(data, forKey: customPresetsKey)
        }
    }

    // MARK: - Meter Timer

    private func startMeterPolling() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isEngineRunning else { return }
                let (inDb, outDb, grDb) = self.engine.readTelemetry()

                let anyWindowVisible = NSApp?.windows.contains(where: { $0.isVisible && !$0.isMiniaturized }) ?? true
                if anyWindowVisible {
                    let nextIn = self.smoothMeter(current: self.meters.inputMeterDb, target: inDb)
                    let nextOut = self.smoothMeter(current: self.meters.outputMeterDb, target: outDb)
                    let nextGr = self.meters.gainReductionDb * 0.65 + grDb * 0.35

                    if abs(nextIn - self.meters.inputMeterDb) > 0.3 { self.meters.inputMeterDb = nextIn }
                    if abs(nextOut - self.meters.outputMeterDb) > 0.3 { self.meters.outputMeterDb = nextOut }
                    if abs(nextGr - self.meters.gainReductionDb) > 0.2 { self.meters.gainReductionDb = nextGr }
                }

                // Sync voice check recording auto-finish
                if self.isRecordingCheck {
                    self.checkRecordingProgress = self.engine.voiceCheckRecordingProgress
                    if !self.engine.isRecordingVoiceCheck {
                        self.isRecordingCheck = false
                        self.hasRecordedCheck = self.engine.hasRecordedVoiceCheck
                        if self.hasRecordedCheck {
                            self.startLoopPlayback()
                        }
                    }
                }
            }
        }
    }

    private func smoothMeter(current: Float, target: Float) -> Float {
        if target > current {
            return current * 0.3 + target * 0.7
        } else {
            return current * 0.84 + target * 0.16
        }
    }
}
