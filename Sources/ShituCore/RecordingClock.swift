import Foundation

/// A monotonic active-time clock; callers supply system uptime, not wall-clock dates.
public struct RecordingClock {
    private var accumulated: TimeInterval = 0
    private var runningSince: TimeInterval?
    public init() {}
    public mutating func start(at now: TimeInterval) { accumulated = 0; runningSince = now }
    public mutating func pause(at now: TimeInterval) {
        guard let start = runningSince else { return }
        accumulated += max(0, now - start); runningSince = nil
    }
    public mutating func resume(at now: TimeInterval) {
        guard runningSince == nil else { return }
        runningSince = now
    }
    public func elapsed(at now: TimeInterval) -> TimeInterval {
        accumulated + (runningSince.map { max(0, now - $0) } ?? 0)
    }
}

