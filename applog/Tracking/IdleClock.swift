import CoreGraphics

/// Seconds since the last keyboard/mouse event, system-wide. This alone is
/// enough for idle detection (FR-8) — no Input Monitoring entitlement needed,
/// since we never read event content, only the aggregate timestamp.
nonisolated enum IdleClock {
    static func secondsSinceLastInput() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .init(rawValue: ~0)!)
    }
}
