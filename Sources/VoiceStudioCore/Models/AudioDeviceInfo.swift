import CoreAudio
import Foundation

public struct AudioDeviceInfo: Identifiable, Equatable, Hashable, Sendable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let manufacturer: String
    public let inputChannels: Int
    public let outputChannels: Int
    public let sampleRate: Double
    public let isVirtual: Bool

    public init(
        id: AudioDeviceID,
        uid: String,
        name: String,
        manufacturer: String,
        inputChannels: Int,
        outputChannels: Int,
        sampleRate: Double,
        isVirtual: Bool
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.manufacturer = manufacturer
        self.inputChannels = inputChannels
        self.outputChannels = outputChannels
        self.sampleRate = sampleRate
        self.isVirtual = isVirtual
    }

    public var isBlackHole: Bool {
        name.localizedCaseInsensitiveContains("BlackHole") ||
        uid.localizedCaseInsensitiveContains("BlackHole")
    }

    public var isAppLoopbackVirtualDevice: Bool {
        name.localizedCaseInsensitiveContains("Microsoft Teams") ||
        uid.localizedCaseInsensitiveContains("MSTeams") ||
        name.localizedCaseInsensitiveContains("ZoomAudioDevice") ||
        uid.localizedCaseInsensitiveContains("ZoomAudio") ||
        name.localizedCaseInsensitiveContains("Steam Streaming")
    }

    public var isExternalPhysicalMic: Bool {
        inputChannels > 0 &&
        !isVirtual &&
        !isBlackHole &&
        !isAppLoopbackVirtualDevice &&
        !name.localizedCaseInsensitiveContains("MacBook") &&
        !name.localizedCaseInsensitiveContains("iPhone")
    }
}
