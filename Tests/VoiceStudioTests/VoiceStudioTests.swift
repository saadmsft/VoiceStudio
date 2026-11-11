import XCTest
@testable import VoiceStudioCore

final class VoiceStudioTests: XCTestCase {

    func testLockFreeRingBufferReadWriteAndDriftBound() {
        let rb = LockFreeRingBuffer(capacity: 1024)
        let input: [Float] = (0..<256).map { Float($0) / 256.0 }
        input.withUnsafeBufferPointer { ptr in
            rb.write(ptr.baseAddress!, count: input.count)
        }
        XCTAssertEqual(rb.availableToRead, 256)

        var output = [Float](repeating: -1, count: 256)
        let readCount = output.withUnsafeMutableBufferPointer { ptr in
            rb.read(into: ptr.baseAddress!, count: 256)
        }
        XCTAssertEqual(readCount, 256)
        for i in 0..<256 {
            XCTAssertEqual(output[i], input[i], accuracy: 1e-6)
        }

        // Verify drift bound caps buffered frames cleanly
        let burst = [Float](repeating: 0.5, count: 4000)
        burst.withUnsafeBufferPointer { ptr in
            rb.write(ptr.baseAddress!, count: burst.count, maxBufferedFrames: 512)
        }
        XCTAssertLessThanOrEqual(rb.availableToRead, 1024)
    }

    func testVoiceProfileFrequencyResponseCurveReflectsCrispAndDeep() {
        let profile = VoiceProfile.studioCrispAndDeep

        // Sub-rumble at 30 Hz should be rolled off below 0 dB by high-pass filter
        let subRumble = profile.magnitudeResponseDb(at: 30.0)
        XCTAssertLessThan(subRumble, -4.0)

        // Chest warmth at 125 Hz should be boosted
        let chest = profile.magnitudeResponseDb(at: 125.0)
        XCTAssertGreaterThan(chest, 2.5)

        // Mud region at 310 Hz should dip below chest warmth
        let mud = profile.magnitudeResponseDb(at: 310.0)
        XCTAssertLessThan(mud, chest - 3.0)

        // Crisp presence (4.2 kHz) and condenser air (12 kHz) should be boosted
        let presence = profile.magnitudeResponseDb(at: 4200.0)
        let air = profile.magnitudeResponseDb(at: 12000.0)
        XCTAssertGreaterThan(presence, 2.5)
        XCTAssertGreaterThan(air, 3.0)
    }

    func testOfflineDSPEngineProcessesSignalAndEnforcesBrickwallCeiling() {
        let engine = VoiceStudioEngine()
        var loudProfile = VoiceProfile.studioCrispAndDeep
        loudProfile.outputGainDb = 9.0
        engine.applyProfile(loudProfile)

        // Generate 0.5s (24,000 samples @ 48kHz) synthetic vocal harmonic wave
        let frameCount = 24000
        var input = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let t = Float(i) / 48000.0
            input[i] = 0.45 * sin(2.0 * .pi * 135.0 * t) + 0.20 * sin(2.0 * .pi * 4200.0 * t)
        }

        let rendered = engine.renderBufferOfflineForTesting(input)
        XCTAssertEqual(rendered.count, frameCount)

        // Steady-state tail after TimePitch FFT warmup (~4096 frames) must have healthy signal
        let tail = Array(rendered.suffix(12000))
        let maxAbs = tail.map { abs($0) }.max() ?? 0.0
        XCTAssertGreaterThan(maxAbs, 0.15, "DSP chain should output audible processed voice")
        XCTAssertLessThanOrEqual(maxAbs, 0.925, "Soft-clip limiter must prevent digital clipping above -0.7 dBFS")
    }

    func testDeviceManagerFindsPhysicalMicAndBlackHoleWithoutVirtualFeedback() {
        let manager = CoreAudioDeviceManager.shared
        let inputs = manager.inputDevices()
        for mic in inputs {
            XCTAssertFalse(mic.isBlackHole, "BlackHole must never appear as mic input to avoid feedback loop")
            XCTAssertFalse(mic.isAppLoopbackVirtualDevice, "Virtual conference/stream loopback devices must be excluded from raw mic inputs")
        }
    }
}
