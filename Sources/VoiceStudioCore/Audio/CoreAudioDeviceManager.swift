import CoreAudio
import Foundation

public final class CoreAudioDeviceManager: @unchecked Sendable {
    public static let shared = CoreAudioDeviceManager()

    private var listenerBlock: AudioObjectPropertyListenerBlock?
    public var onDevicesChanged: (() -> Void)?

    private init() {
        installHardwareListeners()
    }

    public func allDevices() -> [AudioDeviceInfo] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return []
        }

        return deviceIDs.compactMap { queryDeviceInfo(id: $0) }
    }

    public func inputDevices() -> [AudioDeviceInfo] {
        allDevices().filter { $0.inputChannels > 0 && !$0.isBlackHole && !$0.isTeamsVirtualDevice }
    }

    public func outputDevices() -> [AudioDeviceInfo] {
        allDevices().filter { $0.outputChannels > 0 }
    }

    public func monitorDevices() -> [AudioDeviceInfo] {
        allDevices().filter { $0.outputChannels > 0 && !$0.isBlackHole && !$0.isTeamsVirtualDevice }
    }

    public func systemDefaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &devID
        ) == noErr, devID != kAudioObjectUnknown else {
            return nil
        }
        return devID
    }

    public func systemDefaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &devID
        ) == noErr, devID != kAudioObjectUnknown else {
            return nil
        }
        return devID
    }

    /// Picks the best physical microphone: dedicated external USB mic first (e.g. Fifine),
    /// then system default physical mic, then built-in MacBook mic.
    public func preferredInputDevice() -> AudioDeviceInfo? {
        let inputs = inputDevices()
        if let usbMic = inputs.first(where: { $0.isExternalPhysicalMic }) {
            return usbMic
        }
        if let defID = systemDefaultInputDeviceID(),
           let defMic = inputs.first(where: { $0.id == defID }) {
            return defMic
        }
        if let builtIn = inputs.first(where: { $0.name.localizedCaseInsensitiveContains("MacBook") }) {
            return builtIn
        }
        return inputs.first
    }

    /// Automatically selects BlackHole 2ch (or other virtual audio cable) for Microsoft Teams input.
    public func preferredTeamsVirtualOutput() -> AudioDeviceInfo? {
        let outputs = outputDevices()
        if let blackHole = outputs.first(where: { $0.isBlackHole }) {
            return blackHole
        }
        if let virtualCable = outputs.first(where: {
            $0.isVirtual && !$0.isTeamsVirtualDevice
        }) {
            return virtualCable
        }
        return outputs.first
    }

    /// Selects headphones/speakers for live self-monitoring & 5s voice check playback (never BlackHole).
    public func preferredMonitorOutput() -> AudioDeviceInfo? {
        let monitors = monitorDevices()
        if let defOutID = systemDefaultOutputDeviceID(),
           let defMonitor = monitors.first(where: { $0.id == defOutID }) {
            return defMonitor
        }
        if let speakers = monitors.first(where: { $0.name.localizedCaseInsensitiveContains("Speakers") || $0.name.localizedCaseInsensitiveContains("Headphones") }) {
            return speakers
        }
        return monitors.first
    }

    private func queryDeviceInfo(id: AudioDeviceID) -> AudioDeviceInfo? {
        let name = getStringProperty(id: id, selector: kAudioObjectPropertyName) ?? "Unknown Audio Device"
        let uid = getStringProperty(id: id, selector: kAudioDevicePropertyDeviceUID) ?? "\(id)"
        let manufacturer = getStringProperty(id: id, selector: kAudioObjectPropertyManufacturer) ?? ""

        let inChannels = channelCount(id: id, scope: kAudioDevicePropertyScopeInput)
        let outChannels = channelCount(id: id, scope: kAudioDevicePropertyScopeOutput)
        guard inChannels > 0 || outChannels > 0 else { return nil }

        var srAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate: Float64 = 48000.0
        var srSize = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(id, &srAddress, 0, nil, &srSize, &sampleRate)

        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var trSize = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &transportAddress, 0, nil, &trSize, &transport)
        let isVirtual = (transport == kAudioDeviceTransportTypeVirtual)

        return AudioDeviceInfo(
            id: id,
            uid: uid,
            name: name,
            manufacturer: manufacturer,
            inputChannels: inChannels,
            outputChannels: outChannels,
            sampleRate: sampleRate,
            isVirtual: isVirtual
        )
    }

    private func getStringProperty(id: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfStr: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &cfStr)
        guard status == noErr, let value = cfStr?.takeUnretainedValue() else { return nil }
        return value as String
    }

    private func channelCount(id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let rawPtr = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPtr.deallocate() }
        let ablPtr = rawPtr.assumingMemoryBound(to: AudioBufferList.self)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, ablPtr) == noErr else {
            return 0
        }
        let buffers = UnsafeMutableAudioBufferListPointer(ablPtr)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func installHardwareListeners() {
        var devicesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.onDevicesChanged?()
            }
        }
        self.listenerBlock = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddr,
            DispatchQueue.main,
            block
        )
    }
}
