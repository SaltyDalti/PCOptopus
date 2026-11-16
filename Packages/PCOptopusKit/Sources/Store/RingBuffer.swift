import Foundation
import Model

/// In-memory ring of fast samples (about 5 minutes at 2s cadence ≈ 150 slots).
public final class RingBuffer: @unchecked Sendable {
    private var slots: [SampleBundle]
    private var index: Int = 0
    private let capacity: Int
    private let lock = NSLock()

    public init(capacity: Int = 150) {
        self.capacity = capacity
        self.slots = []
        self.slots.reserveCapacity(capacity)
    }

    public func append(_ bundle: SampleBundle) {
        lock.lock()
        defer { lock.unlock() }
        if slots.count < capacity {
            slots.append(bundle)
        } else {
            slots[index % capacity] = bundle
            index += 1
        }
    }

    public func latest() -> SampleBundle? {
        lock.lock()
        defer { lock.unlock() }
        if slots.isEmpty { return nil }
        if slots.count < capacity {
            return slots.last
        }
        let latestIndex = (index - 1 + capacity) % capacity
        return slots[latestIndex]
    }

    public func allChronological() -> [SampleBundle] {
        lock.lock()
        defer { lock.unlock() }
        if slots.count < capacity {
            return slots
        }
        let start = index % capacity
        return Array(slots[start...]) + Array(slots[..<start])
    }
}
