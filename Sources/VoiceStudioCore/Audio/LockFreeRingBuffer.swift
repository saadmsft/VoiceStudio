import Darwin
import Foundation

/// Real-time safe Single-Producer Single-Consumer (SPSC) Float ring buffer.
/// Uses pre-allocated unmanaged memory and OS memory barriers with zero heap allocations
/// during audio IO callbacks. Automatically recovers smoothly from clock drift underrun/overrun.
public final class LockFreeRingBuffer: @unchecked Sendable {
    private let capacity: Int
    private let mask: Int
    private let storage: UnsafeMutablePointer<Float>

    // Aligned 64-bit indices (monotonic counters; masked on access)
    private let writeIndexPtr: UnsafeMutablePointer<Int64>
    private let readIndexPtr: UnsafeMutablePointer<Int64>
    private var lastSample: Float = 0.0

    /// `capacityPowerOfTwo` is rounded up to the next power of two (e.g. 16384 = ~340ms @ 48kHz).
    public init(capacity: Int = 16384) {
        var pow2 = 1024
        while pow2 < capacity { pow2 <<= 1 }
        self.capacity = pow2
        self.mask = pow2 - 1

        self.storage = UnsafeMutablePointer<Float>.allocate(capacity: pow2)
        self.storage.initialize(repeating: 0.0, count: pow2)

        self.writeIndexPtr = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
        self.writeIndexPtr.initialize(to: 0)

        self.readIndexPtr = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
        self.readIndexPtr.initialize(to: 0)
    }

    deinit {
        storage.deallocate()
        writeIndexPtr.deallocate()
        readIndexPtr.deallocate()
    }

    public var availableToRead: Int {
        let w = writeIndexPtr.pointee
        let r = readIndexPtr.pointee
        return max(0, min(capacity, Int(w - r)))
    }

    public func reset() {
        let w = writeIndexPtr.pointee
        readIndexPtr.pointee = w
        lastSample = 0.0
    }

    /// Producer (Real-Time Input Callback): pushes `count` mono samples.
    /// If consumer lags due to clock skew or startup, oldest samples are skipped cleanly
    /// so latency stays tightly bounded (~10-20ms) instead of accumulating delay!
    @inline(__always)
    public func write(_ source: UnsafePointer<Float>, count: Int, maxBufferedFrames: Int = 1920) {
        guard count > 0 else { return }
        var w = writeIndexPtr.pointee
        let r = readIndexPtr.pointee

        // Keep latency bounded if producer runs slightly faster than consumer clock
        let currentFill = Int(w - r)
        if currentFill + count > min(capacity - 64, maxBufferedFrames) {
            let targetFill = max(512, maxBufferedFrames / 2)
            let newRead = w + Int64(count) - Int64(targetFill)
            if newRead > r {
                OSAtomicCompareAndSwap64Barrier(r, newRead, readIndexPtr)
            }
        }

        for i in 0..<count {
            storage[Int(w) & mask] = source[i]
            w &+= 1
        }
        OSMemoryBarrier()
        writeIndexPtr.pointee = w
    }

    /// Consumer (Real-Time Output Callback): reads `count` mono samples.
    /// On brief underrun, decays `lastSample` smoothly to zero to avoid audible clicks.
    @discardableResult
    @inline(__always)
    public func read(into dest: UnsafeMutablePointer<Float>, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let w = writeIndexPtr.pointee
        var r = readIndexPtr.pointee
        OSMemoryBarrier()

        let avail = max(0, Int(w - r))
        let toRead = min(count, avail)

        for i in 0..<toRead {
            let s = storage[Int(r) & mask]
            dest[i] = s
            lastSample = s
            r &+= 1
        }

        if toRead < count {
            for i in toRead..<count {
                lastSample *= 0.92
                dest[i] = lastSample
            }
        }

        OSMemoryBarrier()
        readIndexPtr.pointee = r
        return toRead
    }
}
