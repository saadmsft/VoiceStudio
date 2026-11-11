import AVFoundation
import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

/// Atomic-style flat struct shared with real-time audio callbacks (no reference types or ARC).
public struct RealtimeDSPState {
    public var isMuted: Bool = false
    public var isBypassed: Bool = false
    public var inputGainLinear: Float = 1.0
    public var outputGainLinear: Float = 1.18
    public var subWarmth: Float = 0.24
    public var deEsserAmount: Float = 0.35
    public var monitorEnabled: Bool = false
    public var monitorVolume: Float = 0.85

    // Voice Check (5s Record & Live-Loop Tweak)
    public var isRecordingCheck: Bool = false
    public var isPlayingCheckLoop: Bool = false
    public var checkCompareRawOriginal: Bool = false
    public var recordedFramesCount: Int = 0
    public var recordedWriteCursor: Int = 0
    public var recordedReadCursor: Int = 0

    // Real-time Meter Telemetry (written by audio thread, polled at 60Hz by UI)
    public var inputPeakLinear: Float = 0.0
    public var outputPeakLinear: Float = 0.0
    public var gainReductionDb: Float = 0.0
}

public final class VoiceStudioEngine: @unchecked Sendable {
    public static let sampleRate: Double = 48000.0
    public static let maxVoiceCheckSeconds: Int = 6
    public static let maxVoiceCheckFrames: Int = 48000 * 6

    private let micRingBuffer = LockFreeRingBuffer(capacity: 32768)
    private let monitorRingBuffer = LockFreeRingBuffer(capacity: 32768)

    // Pre-allocated unmanaged buffers for zero-allocation real-time audio rendering
    fileprivate let rtStatePtr: UnsafeMutablePointer<RealtimeDSPState>
    fileprivate let voiceCheckBufferPtr: UnsafeMutablePointer<Float>
    fileprivate let inputScratchPtr: UnsafeMutablePointer<Float>
    fileprivate let resampleScratchPtr: UnsafeMutablePointer<Float>
    fileprivate let dspPullMonoPtr: UnsafeMutablePointer<Float>
    fileprivate let monitorStereoScratchPtr: UnsafeMutablePointer<Float>

    fileprivate var inputHardwareSampleRate: Double = 48000.0
    fileprivate var resamplePhase: Double = 0.0
    fileprivate var prevInputSample: Float = 0.0

    fileprivate var subExciter = SubHarmonicExciter(sampleRate: 48000.0)
    fileprivate var deEsser = DynamicDeEsser(sampleRate: 48000.0)
    fileprivate let softLimiter = SoftClipLimiter()

    // CoreAudio AUHAL Units
    private var inputAUHAL: AudioUnit?
    private var primaryOutputAUHAL: AudioUnit?
    private var monitorOutputAUHAL: AudioUnit?

    // Internal Realtime AVAudioEngine hosting Apple's vDSP Pitch + 6-band EQ + DynamicsProcessor
    private var dspEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var timePitchNode: AVAudioUnitTimePitch?
    private var eqNode: AVAudioUnitEQ?
    private var dynamicsNode: AVAudioUnitEffect?
    fileprivate var manualRenderBlock: AVAudioEngineManualRenderingBlock?
    fileprivate var renderPCMBuffer: AVAudioPCMBuffer?

    public private(set) var isRunning: Bool = false
    public private(set) var activeInputDeviceID: AudioDeviceID?
    public private(set) var activeOutputDeviceID: AudioDeviceID?
    public private(set) var activeMonitorDeviceID: AudioDeviceID?
    public private(set) var currentProfile: VoiceProfile = .teamsCrispAndDeep

    public init() {
        rtStatePtr = UnsafeMutablePointer<RealtimeDSPState>.allocate(capacity: 1)
        rtStatePtr.initialize(to: RealtimeDSPState())

        voiceCheckBufferPtr = UnsafeMutablePointer<Float>.allocate(capacity: Self.maxVoiceCheckFrames)
        voiceCheckBufferPtr.initialize(repeating: 0.0, count: Self.maxVoiceCheckFrames)

        let maxFrames = 8192
        inputScratchPtr = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
        inputScratchPtr.initialize(repeating: 0.0, count: maxFrames)

        resampleScratchPtr = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames * 2)
        resampleScratchPtr.initialize(repeating: 0.0, count: maxFrames * 2)

        dspPullMonoPtr = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
        dspPullMonoPtr.initialize(repeating: 0.0, count: maxFrames)

        monitorStereoScratchPtr = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
        monitorStereoScratchPtr.initialize(repeating: 0.0, count: maxFrames)

        setupRealtimeDSPEngine()
        applyProfile(.teamsCrispAndDeep)
    }

    deinit {
        stop()
        rtStatePtr.deallocate()
        voiceCheckBufferPtr.deallocate()
        inputScratchPtr.deallocate()
        resampleScratchPtr.deallocate()
        dspPullMonoPtr.deallocate()
        monitorStereoScratchPtr.deallocate()
    }

    // MARK: - Internal Realtime DSP Graph Setup

    private func setupRealtimeDSPEngine() {
        let engine = AVAudioEngine()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2) else {
            return
        }

        let statePtr = self.rtStatePtr
        let pullMono = self.dspPullMonoPtr
        let checkBuf = self.voiceCheckBufferPtr
        let micRB = self.micRingBuffer

        let srcNode = AVAudioSourceNode(format: format) { [unowned self] _, _, frameCount, audioBufferList -> OSStatus in
            let count = min(Int(frameCount), 4096)
            let isLooping = statePtr.pointee.isPlayingCheckLoop && statePtr.pointee.recordedFramesCount > 4800

            if isLooping {
                let total = statePtr.pointee.recordedFramesCount
                var cursor = statePtr.pointee.recordedReadCursor
                for i in 0..<count {
                    pullMono[i] = checkBuf[cursor]
                    cursor += 1
                    if cursor >= total { cursor = 0 }
                }
                statePtr.pointee.recordedReadCursor = cursor
            } else {
                micRB.read(into: pullMono, count: count)
            }

            let inGain = statePtr.pointee.inputGainLinear
            let warmthAmt = statePtr.pointee.subWarmth
            let deEssAmt = statePtr.pointee.deEsserAmount

            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let leftPtr = abl[0].mData?.assumingMemoryBound(to: Float.self)
            let rightPtr = abl.count > 1 ? abl[1].mData?.assumingMemoryBound(to: Float.self) : nil

            for i in 0..<count {
                var s = pullMono[i] * inGain
                s = self.subExciter.process(s, amount: warmthAmt)
                s = self.deEsser.process(s, amount: deEssAmt)
                leftPtr?[i] = s
                rightPtr?[i] = s
            }
            return noErr
        }

        let tp = AVAudioUnitTimePitch()
        tp.rate = 1.0
        tp.overlap = 8.0

        let eq = AVAudioUnitEQ(numberOfBands: 6)
        configureEQBands(eq)

        let dynDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        let dyn = AVAudioUnitEffect(audioComponentDescription: dynDesc)

        do {
            try engine.enableManualRenderingMode(.realtime, format: format, maximumFrameCount: 4096)
            engine.attach(srcNode)
            engine.attach(tp)
            engine.attach(eq)
            engine.attach(dyn)

            engine.connect(srcNode, to: tp, format: format)
            engine.connect(tp, to: eq, format: format)
            engine.connect(eq, to: dyn, format: format)
            engine.connect(dyn, to: engine.mainMixerNode, format: format)

            try engine.start()

            // Enable spectral coherence & transient preservation on TimePitch
            if let tree = tp.auAudioUnit.parameterTree {
                tree.parameter(withAddress: 6)?.value = 1.0 // Spectral Coherence
                tree.parameter(withAddress: 7)?.value = 1.0 // Preserve Transients
            }

            self.dspEngine = engine
            self.sourceNode = srcNode
            self.timePitchNode = tp
            self.eqNode = eq
            self.dynamicsNode = dyn
            self.manualRenderBlock = engine.manualRenderingBlock
            self.renderPCMBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)
        } catch {
            print("VoiceStudioEngine: Failed to start internal DSP engine: \(error)")
        }
    }

    private func configureEQBands(_ eq: AVAudioUnitEQ) {
        // Band 0: High-Pass Rumble Filter
        eq.bands[0].filterType = .highPass
        eq.bands[0].frequency = 80.0
        eq.bands[0].bypass = false

        // Band 1: Chest Warmth / Studio Proximity @ 125 Hz
        eq.bands[1].filterType = .parametric
        eq.bands[1].frequency = 125.0
        eq.bands[1].bandwidth = 1.0
        eq.bands[1].gain = 3.5
        eq.bands[1].bypass = false

        // Band 2: Boxiness / Mud Cleanup @ 310 Hz
        eq.bands[2].filterType = .parametric
        eq.bands[2].frequency = 310.0
        eq.bands[2].bandwidth = 0.7
        eq.bands[2].gain = -2.5
        eq.bands[2].bypass = false

        // Band 3: Subtle Nasal Smoothness @ 950 Hz
        eq.bands[3].filterType = .parametric
        eq.bands[3].frequency = 950.0
        eq.bands[3].bandwidth = 0.8
        eq.bands[3].gain = -0.8
        eq.bands[3].bypass = false

        // Band 4: Vocal Crispness & Articulation @ 4200 Hz
        eq.bands[4].filterType = .parametric
        eq.bands[4].frequency = 4200.0
        eq.bands[4].bandwidth = 0.9
        eq.bands[4].gain = 3.8
        eq.bands[4].bypass = false

        // Band 5: Studio Condenser Air High-Shelf @ 9500 Hz
        eq.bands[5].filterType = .highShelf
        eq.bands[5].frequency = 9500.0
        eq.bands[5].gain = 4.5
        eq.bands[5].bypass = false
    }

    // MARK: - Profile & Real-time Parameter Updates

    public func applyProfile(_ profile: VoiceProfile) {
        self.currentProfile = profile

        rtStatePtr.pointee.inputGainLinear = pow(10.0, profile.inputGainDb / 20.0)
        rtStatePtr.pointee.outputGainLinear = pow(10.0, profile.outputGainDb / 20.0)
        rtStatePtr.pointee.subWarmth = max(0.0, min(1.0, profile.subWarmth))
        rtStatePtr.pointee.deEsserAmount = max(0.0, min(1.0, profile.deEsserAmount))

        if let tp = timePitchNode {
            let clampedCents = max(-600.0, min(600.0, profile.pitchCents))
            tp.pitch = clampedCents
            tp.bypass = abs(clampedCents) < 1.0
        }

        if let eq = eqNode {
            eq.bands[0].frequency = max(35.0, min(180.0, profile.lowCutHz))
            eq.bands[1].gain = max(-6.0, min(12.0, profile.chestWarmthDb))
            eq.bands[2].gain = -max(0.0, min(8.0, profile.mudCutDb))
            eq.bands[4].gain = max(-6.0, min(12.0, profile.presenceDb))
            eq.bands[5].gain = max(-6.0, min(12.0, profile.airDb))
        }

        if let dynUnit = dynamicsNode?.audioUnit {
            let comp = max(0.0, min(1.0, profile.compressionAmount))
            // Map 0..1 compression into musical studio threshold, headroom, attack/release & auto-makeup
            let thresholdDb: Float = -12.0 - comp * 20.0      // -12 dB .. -32 dB
            let headroomDb: Float = 24.0 - comp * 20.0       // gentle 24 dB .. firm 4 dB (~6:1)
            let makeupDb: Float = comp * 5.2                 // automatic loudness compensation

            let gateRatio: Float = profile.gateEnabled ? 6.5 : 1.0
            let gateThresh: Float = profile.gateEnabled ? max(-90.0, min(-20.0, profile.gateThresholdDb)) : -115.0

            AudioUnitSetParameter(dynUnit, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, thresholdDb, 0)
            AudioUnitSetParameter(dynUnit, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, max(1.5, headroomDb), 0)
            AudioUnitSetParameter(dynUnit, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, gateRatio, 0)
            AudioUnitSetParameter(dynUnit, kDynamicsProcessorParam_ExpansionThreshold, kAudioUnitScope_Global, 0, gateThresh, 0)
            AudioUnitSetParameter(dynUnit, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.008, 0)
            AudioUnitSetParameter(dynUnit, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.140, 0)
            AudioUnitSetParameter(dynUnit, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, makeupDb, 0)
        }
    }

    public var isMuted: Bool {
        get { rtStatePtr.pointee.isMuted }
        set { rtStatePtr.pointee.isMuted = newValue }
    }

    public var isBypassed: Bool {
        get { rtStatePtr.pointee.isBypassed }
        set { rtStatePtr.pointee.isBypassed = newValue }
    }

    public var monitorVolume: Float {
        get { rtStatePtr.pointee.monitorVolume }
        set { rtStatePtr.pointee.monitorVolume = max(0.0, min(1.2, newValue)) }
    }

    // MARK: - Start / Stop / Device Routing

    public func start(
        inputDeviceID: AudioDeviceID,
        outputDeviceID: AudioDeviceID,
        monitorDeviceID: AudioDeviceID?,
        enableLiveMonitor: Bool
    ) throws {
        stop()

        micRingBuffer.reset()
        monitorRingBuffer.reset()
        subExciter.reset()
        deEsser.reset()

        if dspEngine?.isRunning != true {
            try dspEngine?.start()
        }

        try startInputAUHAL(deviceID: inputDeviceID)
        try startPrimaryOutputAUHAL(deviceID: outputDeviceID)

        self.activeInputDeviceID = inputDeviceID
        self.activeOutputDeviceID = outputDeviceID
        self.activeMonitorDeviceID = monitorDeviceID
        rtStatePtr.pointee.monitorEnabled = enableLiveMonitor

        if let monID = monitorDeviceID, (enableLiveMonitor || rtStatePtr.pointee.isPlayingCheckLoop) {
            try? startMonitorOutputAUHAL(deviceID: monID)
        }

        isRunning = true
    }

    public func stop() {
        stopAUHAL(&inputAUHAL)
        stopAUHAL(&primaryOutputAUHAL)
        stopAUHAL(&monitorOutputAUHAL)
        isRunning = false
    }

    public func setLiveMonitor(enabled: Bool, monitorDeviceID: AudioDeviceID?) {
        let deviceChanged = (self.activeMonitorDeviceID != monitorDeviceID)
        self.activeMonitorDeviceID = monitorDeviceID
        rtStatePtr.pointee.monitorEnabled = enabled
        if deviceChanged {
            stopAUHAL(&monitorOutputAUHAL)
        }
        updateSecondaryMonitorState()
    }

    private func updateSecondaryMonitorState() {
        let needsMonitorUnit = rtStatePtr.pointee.monitorEnabled || rtStatePtr.pointee.isPlayingCheckLoop
        if needsMonitorUnit, let monID = activeMonitorDeviceID, monID != activeOutputDeviceID {
            if monitorOutputAUHAL == nil {
                monitorRingBuffer.reset()
                try? startMonitorOutputAUHAL(deviceID: monID)
            }
        } else {
            stopAUHAL(&monitorOutputAUHAL)
        }
    }

    // MARK: - 5-Second Record & Live-Loop Tweak (Feedback-Free Voice Check!)

    public func startVoiceCheckRecording() {
        rtStatePtr.pointee.isPlayingCheckLoop = false
        rtStatePtr.pointee.recordedWriteCursor = 0
        rtStatePtr.pointee.recordedFramesCount = 0
        rtStatePtr.pointee.isRecordingCheck = true
        updateSecondaryMonitorState()
    }

    public func stopVoiceCheckRecording() -> Double {
        rtStatePtr.pointee.isRecordingCheck = false
        let frames = rtStatePtr.pointee.recordedWriteCursor
        rtStatePtr.pointee.recordedFramesCount = frames
        rtStatePtr.pointee.recordedReadCursor = 0
        return Double(frames) / Self.sampleRate
    }

    public var hasRecordedVoiceCheck: Bool {
        rtStatePtr.pointee.recordedFramesCount > 4800
    }

    public var isRecordingVoiceCheck: Bool {
        rtStatePtr.pointee.isRecordingCheck
    }

    public var isPlayingVoiceCheckLoop: Bool {
        rtStatePtr.pointee.isPlayingCheckLoop
    }

    public var voiceCheckRecordingProgress: Double {
        let current = rtStatePtr.pointee.isRecordingCheck
            ? rtStatePtr.pointee.recordedWriteCursor
            : rtStatePtr.pointee.recordedFramesCount
        return min(1.0, Double(current) / Double(Self.maxVoiceCheckFrames))
    }

    public func setVoiceCheckLoopPlayback(playing: Bool, monitorDeviceID: AudioDeviceID?) {
        if let monitorDeviceID {
            self.activeMonitorDeviceID = monitorDeviceID
        }
        rtStatePtr.pointee.isRecordingCheck = false
        rtStatePtr.pointee.recordedReadCursor = 0
        rtStatePtr.pointee.isPlayingCheckLoop = playing && hasRecordedVoiceCheck
        monitorRingBuffer.reset()
        updateSecondaryMonitorState()
    }

    public var checkCompareRawOriginal: Bool {
        get { rtStatePtr.pointee.checkCompareRawOriginal }
        set { rtStatePtr.pointee.checkCompareRawOriginal = newValue }
    }

    // MARK: - Telemetry Snapshot (60fps UI Polling)

    public func readTelemetry() -> (inputDb: Float, outputDb: Float, gainReductionDb: Float) {
        let inPeak = rtStatePtr.pointee.inputPeakLinear
        let outPeak = rtStatePtr.pointee.outputPeakLinear
        rtStatePtr.pointee.inputPeakLinear *= 0.82
        rtStatePtr.pointee.outputPeakLinear *= 0.82

        var grDb: Float = 0.0
        if let dynUnit = dynamicsNode?.audioUnit {
            AudioUnitGetParameter(dynUnit, kDynamicsProcessorParam_CompressionAmount, kAudioUnitScope_Global, 0, &grDb)
        }

        let inDb = inPeak > 0.00001 ? 20.0 * log10(inPeak) : -90.0
        let outDb = outPeak > 0.00001 ? 20.0 * log10(outPeak) : -90.0
        return (max(-90.0, min(6.0, inDb)), max(-90.0, min(6.0, outDb)), abs(grDb))
    }

    // MARK: - Offline Deterministic Render (for Automated DSP Tests)

    public func renderBufferOfflineForTesting(_ inputMono: [Float]) -> [Float] {
        micRingBuffer.reset()
        subExciter.reset()
        deEsser.reset()

        guard let renderBlock = manualRenderBlock,
              let pcm = renderPCMBuffer else {
            return inputMono
        }

        var output = [Float]()
        output.reserveCapacity(inputMono.count)

        let chunkSize = 256
        var offset = 0
        while offset < inputMono.count {
            let count = min(chunkSize, inputMono.count - offset)
            inputMono.withUnsafeBufferPointer { ptr in
                micRingBuffer.write(ptr.baseAddress! + offset, count: count, maxBufferedFrames: 16384)
            }
            pcm.frameLength = AVAudioFrameCount(count)
            let status = renderBlock(AVAudioFrameCount(count), pcm.mutableAudioBufferList, nil)
            if status == .success, let ch0 = pcm.floatChannelData?[0] {
                let outGain = rtStatePtr.pointee.outputGainLinear
                for i in 0..<count {
                    output.append(softLimiter.process(ch0[i] * outGain))
                }
            } else {
                output.append(contentsOf: repeatElement(0.0, count: count))
            }
            offset += count
        }
        return output
    }

    // MARK: - CoreAudio AUHAL Implementation

    private func startInputAUHAL(deviceID: AudioDeviceID) throws {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let comp = AudioComponentFindNext(nil, &desc) else {
            throw NSError(domain: "VoiceStudioEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "HALOutput component not found"])
        }

        var unit: AudioUnit?
        guard AudioComponentInstanceNew(comp, &unit) == noErr, let au = unit else {
            throw NSError(domain: "VoiceStudioEngine", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create Input AUHAL"])
        }

        var enableIO: UInt32 = 1
        var disableIO: UInt32 = 0
        AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enableIO, UInt32(MemoryLayout<UInt32>.size))
        AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disableIO, UInt32(MemoryLayout<UInt32>.size))

        var devID = deviceID
        let setDevStatus = AudioUnitSetProperty(
            au,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if setDevStatus != noErr {
            AudioComponentInstanceDispose(au)
            throw NSError(domain: "VoiceStudioEngine", code: Int(setDevStatus), userInfo: [NSLocalizedDescriptionKey: "Cannot attach microphone device (\(setDevStatus))"])
        }

        // Request low-latency 256-frame hardware buffer (~5.3ms @ 48kHz)
        var preferredFrames: UInt32 = 256
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(deviceID, &propAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &preferredFrames)

        // Query hardware input stream sample rate
        var hwFormat = AudioStreamBasicDescription()
        var fmtSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        AudioUnitGetProperty(au, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &hwFormat, &fmtSize)
        let hwSR = hwFormat.mSampleRate > 8000 ? hwFormat.mSampleRate : Self.sampleRate
        self.inputHardwareSampleRate = hwSR
        self.resamplePhase = 0.0
        self.prevInputSample = 0.0

        // Client output format from Input Bus 1: Mono Float32 Non-Interleaved at hardware sample rate
        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: hwSR,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &clientFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

        var callbackStruct = AURenderCallbackStruct(
            inputProc: inputAUHALCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        AudioUnitSetProperty(
            au,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &callbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )

        let initStatus = AudioUnitInitialize(au)
        guard initStatus == noErr else {
            AudioComponentInstanceDispose(au)
            throw NSError(domain: "VoiceStudioEngine", code: Int(initStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to initialize microphone (\(initStatus))"])
        }

        let startStatus = AudioOutputUnitStart(au)
        guard startStatus == noErr else {
            AudioUnitUninitialize(au)
            AudioComponentInstanceDispose(au)
            throw NSError(domain: "VoiceStudioEngine", code: Int(startStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to start microphone capture (\(startStatus)). Check macOS Microphone permission."])
        }

        self.inputAUHAL = au
    }

    private func startPrimaryOutputAUHAL(deviceID: AudioDeviceID) throws {
        let au = try createOutputAUHAL(
            deviceID: deviceID,
            callback: primaryOutputAUHALCallback
        )
        self.primaryOutputAUHAL = au
    }

    private func startMonitorOutputAUHAL(deviceID: AudioDeviceID) throws {
        let au = try createOutputAUHAL(
            deviceID: deviceID,
            callback: monitorOutputAUHALCallback
        )
        self.monitorOutputAUHAL = au
    }

    private func createOutputAUHAL(deviceID: AudioDeviceID, callback: @escaping AURenderCallback) throws -> AudioUnit {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let comp = AudioComponentFindNext(nil, &desc) else {
            throw NSError(domain: "VoiceStudioEngine", code: -10, userInfo: [NSLocalizedDescriptionKey: "Output HAL component missing"])
        }

        var unit: AudioUnit?
        guard AudioComponentInstanceNew(comp, &unit) == noErr, let au = unit else {
            throw NSError(domain: "VoiceStudioEngine", code: -11, userInfo: [NSLocalizedDescriptionKey: "Failed to instantiate Output AUHAL"])
        }

        var devID = deviceID
        let setStatus = AudioUnitSetProperty(
            au,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if setStatus != noErr {
            AudioComponentInstanceDispose(au)
            throw NSError(domain: "VoiceStudioEngine", code: Int(setStatus), userInfo: [NSLocalizedDescriptionKey: "Cannot attach output device (\(setStatus))"])
        }

        var preferredFrames: UInt32 = 256
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(deviceID, &propAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &preferredFrames)

        var streamFormat = AudioStreamBasicDescription(
            mSampleRate: Self.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        AudioUnitSetProperty(
            au,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &streamFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )

        var cb = AURenderCallbackStruct(
            inputProc: callback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        AudioUnitSetProperty(
            au,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            0,
            &cb,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )

        let initStatus = AudioUnitInitialize(au)
        guard initStatus == noErr else {
            AudioComponentInstanceDispose(au)
            throw NSError(domain: "VoiceStudioEngine", code: Int(initStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to initialize output (\(initStatus))"])
        }

        let startStatus = AudioOutputUnitStart(au)
        guard startStatus == noErr else {
            AudioUnitUninitialize(au)
            AudioComponentInstanceDispose(au)
            throw NSError(domain: "VoiceStudioEngine", code: Int(startStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to start output (\(startStatus))"])
        }

        return au
    }

    private func stopAUHAL(_ unit: inout AudioUnit?) {
        guard let au = unit else { return }
        AudioOutputUnitStop(au)
        AudioUnitUninitialize(au)
        AudioComponentInstanceDispose(au)
        unit = nil
    }

    // MARK: - Real-Time Render Handlers

    fileprivate func handleInputCallback(
        ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        inTimeStamp: UnsafePointer<AudioTimeStamp>,
        inNumberFrames: UInt32
    ) -> OSStatus {
        guard let au = inputAUHAL else { return noErr }
        let frames = min(Int(inNumberFrames), 4096)

        let buffer = AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: UInt32(frames * 4),
            mData: UnsafeMutableRawPointer(inputScratchPtr)
        )
        var abl = AudioBufferList(mNumberBuffers: 1, mBuffers: buffer)

        let status = AudioUnitRender(au, ioActionFlags, inTimeStamp, 1, UInt32(frames), &abl)
        guard status == noErr else { return status }

        // Measure raw mic peak for input meter
        var localPeak: Float = 0.0
        for i in 0..<frames {
            let a = abs(inputScratchPtr[i])
            if a > localPeak { localPeak = a }
        }
        if localPeak > rtStatePtr.pointee.inputPeakLinear {
            rtStatePtr.pointee.inputPeakLinear = localPeak
        }

        // Resample to 48kHz if hardware sample rate differs
        let srcPtr: UnsafePointer<Float>
        let outCount: Int
        if abs(inputHardwareSampleRate - Self.sampleRate) < 1.0 {
            srcPtr = UnsafePointer(inputScratchPtr)
            outCount = frames
        } else {
            let ratio = inputHardwareSampleRate / Self.sampleRate
            var produced = 0
            var pos = resamplePhase
            while Int(pos) < frames && produced < 8192 {
                let idx = Int(pos)
                let frac = Float(pos - Double(idx))
                let s0 = idx == 0 ? prevInputSample : inputScratchPtr[idx - 1]
                let s1 = inputScratchPtr[idx]
                resampleScratchPtr[produced] = s0 + frac * (s1 - s0)
                produced += 1
                pos += ratio
            }
            if frames > 0 {
                prevInputSample = inputScratchPtr[frames - 1]
            }
            resamplePhase = max(0.0, pos - Double(frames))
            srcPtr = UnsafePointer(resampleScratchPtr)
            outCount = produced
        }

        // Capture into 5-second Voice Check recording buffer if recording
        if rtStatePtr.pointee.isRecordingCheck {
            var writeIdx = rtStatePtr.pointee.recordedWriteCursor
            let remaining = Self.maxVoiceCheckFrames - writeIdx
            if remaining > 0 {
                let toCopy = min(outCount, remaining)
                for i in 0..<toCopy {
                    voiceCheckBufferPtr[writeIdx + i] = srcPtr[i]
                }
                writeIdx += toCopy
                rtStatePtr.pointee.recordedWriteCursor = writeIdx
                rtStatePtr.pointee.recordedFramesCount = writeIdx
                if writeIdx >= Self.maxVoiceCheckFrames {
                    rtStatePtr.pointee.isRecordingCheck = false
                }
            } else {
                rtStatePtr.pointee.isRecordingCheck = false
            }
        }

        micRingBuffer.write(srcPtr, count: outCount, maxBufferedFrames: 2048)
        return noErr
    }

    fileprivate func handlePrimaryOutputCallback(
        inNumberFrames: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>?
    ) -> OSStatus {
        guard let ioData else { return noErr }
        let frames = min(Int(inNumberFrames), 4096)
        let outABL = UnsafeMutableAudioBufferListPointer(ioData)
        let outL = outABL[0].mData?.assumingMemoryBound(to: Float.self)
        let outR = outABL.count > 1 ? outABL[1].mData?.assumingMemoryBound(to: Float.self) : nil

        // Mute check
        if rtStatePtr.pointee.isMuted {
            for i in 0..<frames {
                outL?[i] = 0.0
                outR?[i] = 0.0
            }
            rtStatePtr.pointee.outputPeakLinear = 0.0
            return noErr
        }

        let isLoopingCheck = rtStatePtr.pointee.isPlayingCheckLoop && rtStatePtr.pointee.recordedFramesCount > 4800

        // Bypass OR Raw A/B comparison during Voice Check loop
        if rtStatePtr.pointee.isBypassed || (isLoopingCheck && rtStatePtr.pointee.checkCompareRawOriginal) {
            if isLoopingCheck {
                let total = rtStatePtr.pointee.recordedFramesCount
                var cursor = rtStatePtr.pointee.recordedReadCursor
                for i in 0..<frames {
                    dspPullMonoPtr[i] = voiceCheckBufferPtr[cursor]
                    cursor += 1
                    if cursor >= total { cursor = 0 }
                }
                rtStatePtr.pointee.recordedReadCursor = cursor
            } else {
                micRingBuffer.read(into: dspPullMonoPtr, count: frames)
            }

            let inGain = rtStatePtr.pointee.inputGainLinear
            var peak: Float = 0.0
            for i in 0..<frames {
                let sample = softLimiter.process(dspPullMonoPtr[i] * inGain)
                let a = abs(sample)
                if a > peak { peak = a }

                if isLoopingCheck {
                    // Silence BlackHole Teams output while listening to local voice check loop
                    outL?[i] = 0.0
                    outR?[i] = 0.0
                } else {
                    outL?[i] = sample
                    outR?[i] = sample
                }
                monitorStereoScratchPtr[i] = sample
            }
            if peak > rtStatePtr.pointee.outputPeakLinear {
                rtStatePtr.pointee.outputPeakLinear = peak
            }
            if rtStatePtr.pointee.monitorEnabled || isLoopingCheck {
                monitorRingBuffer.write(monitorStereoScratchPtr, count: frames, maxBufferedFrames: 2048)
            }
            return noErr
        }

        // Full Broadcast Studio DSP Chain via AVAudioEngine manualRenderingBlock
        guard let renderBlock = manualRenderBlock,
              let pcm = renderPCMBuffer else {
            for i in 0..<frames {
                outL?[i] = 0.0
                outR?[i] = 0.0
            }
            return noErr
        }

        pcm.frameLength = AVAudioFrameCount(frames)
        let renderStatus = renderBlock(AVAudioFrameCount(frames), pcm.mutableAudioBufferList, nil)
        guard renderStatus == .success, let renderedL = pcm.floatChannelData?[0] else {
            for i in 0..<frames {
                outL?[i] = 0.0
                outR?[i] = 0.0
            }
            return noErr
        }
        let renderedR = pcm.floatChannelData?[1] ?? renderedL
        let outGain = rtStatePtr.pointee.outputGainLinear

        var peak: Float = 0.0
        for i in 0..<frames {
            let sL = softLimiter.process(renderedL[i] * outGain)
            let sR = softLimiter.process(renderedR[i] * outGain)
            let a = max(abs(sL), abs(sR))
            if a > peak { peak = a }

            if isLoopingCheck && activeOutputDeviceID != activeMonitorDeviceID {
                // Keep Teams virtual mic quiet while user tweaks recorded loop locally
                outL?[i] = 0.0
                outR?[i] = 0.0
            } else {
                outL?[i] = sL
                outR?[i] = sR
            }
            monitorStereoScratchPtr[i] = 0.5 * (sL + sR)
        }

        if peak > rtStatePtr.pointee.outputPeakLinear {
            rtStatePtr.pointee.outputPeakLinear = peak
        }

        if rtStatePtr.pointee.monitorEnabled || isLoopingCheck {
            monitorRingBuffer.write(monitorStereoScratchPtr, count: frames, maxBufferedFrames: 2048)
        }

        return noErr
    }

    fileprivate func handleMonitorOutputCallback(
        inNumberFrames: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>?
    ) -> OSStatus {
        guard let ioData else { return noErr }
        let frames = min(Int(inNumberFrames), 4096)
        let outABL = UnsafeMutableAudioBufferListPointer(ioData)
        let outL = outABL[0].mData?.assumingMemoryBound(to: Float.self)
        let outR = outABL.count > 1 ? outABL[1].mData?.assumingMemoryBound(to: Float.self) : nil

        let shouldPlay = rtStatePtr.pointee.monitorEnabled || rtStatePtr.pointee.isPlayingCheckLoop
        guard shouldPlay else {
            for i in 0..<frames {
                outL?[i] = 0.0
                outR?[i] = 0.0
            }
            return noErr
        }

        guard let targetL = outL else { return noErr }

        monitorRingBuffer.read(into: targetL, count: frames)
        let vol = rtStatePtr.pointee.monitorVolume
        for i in 0..<frames {
            let s = targetL[i] * vol
            targetL[i] = s
            outR?[i] = s
        }
        return noErr
    }
}

// MARK: - C Function Pointers for CoreAudio AUHAL

private func inputAUHALCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let engine = Unmanaged<VoiceStudioEngine>.fromOpaque(inRefCon).takeUnretainedValue()
    return engine.handleInputCallback(
        ioActionFlags: ioActionFlags,
        inTimeStamp: inTimeStamp,
        inNumberFrames: inNumberFrames
    )
}

private func primaryOutputAUHALCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let engine = Unmanaged<VoiceStudioEngine>.fromOpaque(inRefCon).takeUnretainedValue()
    return engine.handlePrimaryOutputCallback(
        inNumberFrames: inNumberFrames,
        ioData: ioData
    )
}

private func monitorOutputAUHALCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let engine = Unmanaged<VoiceStudioEngine>.fromOpaque(inRefCon).takeUnretainedValue()
    return engine.handleMonitorOutputCallback(
        inNumberFrames: inNumberFrames,
        ioData: ioData
    )
}
