import Foundation
import AppKit

nonisolated enum IdleState: Equatable {
    case active
    case semiIdle
    case fullyIdle
}

/// Owns the sampling loop (design.md §3.2). Runs as an actor so its mutable
/// idle/session state is never touched from two places at once, even though
/// the timer tick and manual pause/resume calls can both come in concurrently.
actor TrackingEngine {
    private let store: Store
    private let settings: SettingsStore

    private var isPaused = false
    private var idleState: IdleState = .active
    private var idleAccumulatorStart: Date?
    private var openSession: (nodeID: Int64, start: Date)?
    private var loopTask: Task<Void, Never>?

    init(store: Store, settings: SettingsStore) {
        self.store = store
        self.settings = settings
    }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task {
            while !Task.isCancelled {
                await self.tick()
                let interval = await MainActor.run { settings.sampleIntervalSeconds }
                try? await Task.sleep(nanoseconds: UInt64(max(1, interval)) * 1_000_000_000)
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused {
            Task { try? await flushOpenSession(endingAt: Date()) }
        }
    }

    func togglePaused() -> Bool {
        isPaused.toggle()
        if isPaused {
            Task { try? await flushOpenSession(endingAt: Date()) }
        }
        return isPaused
    }

    private func tick() async {
        guard !isPaused else { return }

        let (semiIdleThreshold, fullyIdleThreshold, interval) = await MainActor.run {
            (settings.semiIdleThresholdSeconds, settings.fullyIdleThresholdSeconds, settings.sampleIntervalSeconds)
        }
        let idleSeconds = IdleClock.secondsSinceLastInput()

        let newState: IdleState
        if idleSeconds >= Double(fullyIdleThreshold) {
            newState = .fullyIdle
        } else if idleSeconds >= Double(semiIdleThreshold) {
            newState = .semiIdle
        } else {
            newState = .active
        }

        let wasFullyIdle = idleState == .fullyIdle
        idleState = newState

        if newState == .fullyIdle {
            if !wasFullyIdle {
                // Just went idle: close out whatever was being tracked, start
                // accumulating idle time silently. No dialog — FR-7.
                try? await flushOpenSession(endingAt: Date())
                idleAccumulatorStart = Date()
            }
            return
        }

        if wasFullyIdle, let idleStart = idleAccumulatorStart {
            // Coming back from idle: fold the whole idle span into the Away
            // node in one shot, quietly.
            let now = Date()
            do {
                let awayID = try await store.awayNodeID()
                try await store.recordSession(nodeID: awayID, startedAt: idleStart, endedAt: now)
                try await store.addActiveSeconds(
                    Int(now.timeIntervalSince(idleStart)), isSemiIdle: false,
                    keyClicks: 0, mouseClicks: 0, toNode: awayID, day: now
                )
            } catch {
                print("TrackingEngine: failed to flush away time — \(error)")
            }
            idleAccumulatorStart = nil
        }

        guard let app = await MainActor.run(body: { NSWorkspace.shared.frontmostApplication }),
              let bundleID = app.bundleIdentifier else { return }

        let excludedApps = (try? await store.exclusions(kind: .app)) ?? []
        guard !excludedApps.contains(bundleID) else { return }

        let title = await MainActor.run { WindowTitleSampler.frontmostWindowTitle(for: app) }
        let appName = app.localizedName ?? bundleID
        let chain = HierarchyBuilder.chain(bundleID: bundleID, appName: appName, windowTitle: title)

        do {
            var parentID: Int64?
            for level in chain {
                parentID = try await store.findOrCreateNode(
                    parentID: parentID, kind: level.kind, name: level.name,
                    bundleID: level.kind == .app ? bundleID : nil
                )
            }
            guard let leafNodeID = parentID else { return }

            let now = Date()
            if let open = openSession, open.nodeID != leafNodeID {
                try await store.recordSession(nodeID: open.nodeID, startedAt: open.start, endedAt: now)
                openSession = (leafNodeID, now)
            } else if openSession == nil {
                openSession = (leafNodeID, now)
            }

            try await store.addActiveSeconds(
                interval, isSemiIdle: newState == .semiIdle,
                keyClicks: 0, mouseClicks: 0, toNode: leafNodeID, day: now
            )
        } catch {
            print("TrackingEngine: failed to record sample — \(error)")
        }
    }

    private func flushOpenSession(endingAt end: Date) async throws {
        guard let open = openSession else { return }
        try await store.recordSession(nodeID: open.nodeID, startedAt: open.start, endedAt: end)
        openSession = nil
    }
}
