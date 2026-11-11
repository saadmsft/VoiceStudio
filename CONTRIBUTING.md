# Contributing to VoiceStudio 🎙️

Contributions, DSP improvements, preset ideas, and bug reports are welcome!

## Quick Dev Workflow

```bash
git clone https://github.com/saadmsft/VoiceStudio.git
cd VoiceStudio

# Run unit & offline DSP verification tests
swift test

# Build & install locally to ~/Applications/VoiceStudio.app
./scripts/bundle-app.sh
```

## Real-Time Audio Thread Rules (`VoiceStudioCore`)

- **Zero heap allocations, locks, or Objective-C/Swift ARC traffic** inside `handleInputCallback`, `handlePrimaryOutputCallback`, or `handleMonitorOutputCallback`.
- Keep all per-sample filter state in value types (`BiquadFilter`, `SubHarmonicExciter`, `DynamicDeEsser`, `SoftClipLimiter`) or pre-allocated unmanaged buffers (`LockFreeRingBuffer`).
- Add unit or deterministic offline render tests in `Tests/VoiceStudioTests/VoiceStudioTests.swift` for any DSP changes.
