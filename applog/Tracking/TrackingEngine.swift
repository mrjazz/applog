import Foundation
import AppKit
import os

nonisolated enum IdleState: Equatable {
    case active
    case semiIdle
}

/// Owns the sampling loop (design.md §3.2). Runs as an actor so its mutable
/// idle/session state is never touched from two places at once, even though
/// the timer tick and manual pause/resume calls can both come in concurrently.
actor TrackingEngine {
    private let store: Store
    private let settings: SettingsStore

    private var isPaused = false
    private var idleState: IdleState = .active
    private var openSession: (nodeID: Int64, start: Date)?
    private var loopTask: Task<Void, Never>?
    private var lastTickAt: Date?

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

        let now = Date()
        defer { lastTickAt = now }

        let (semiIdleThreshold, interval) = await MainActor.run {
            (settings.semiIdleThresholdSeconds, settings.sampleIntervalSeconds)
        }
        // Credit the actual wall-clock time since the previous tick, not the
        // configured sample interval: tick() itself does synchronous AppleScript
        // and Accessibility calls that can take as long as (or longer than) the
        // interval, and crediting a fixed amount silently drops that overhead.
        // Clamped so a stalled tick (e.g. system sleep) can't over-credit.
        // Missing input is deliberately not used as a cutoff: reading,
        // watching video, and meetings are still screen time.
        let maximumSampleGap = max(Double(interval) * 2, 30)
        let elapsedSeconds = lastTickAt.map { min(now.timeIntervalSince($0), maximumSampleGap) } ?? Double(interval)
        let idleSeconds = IdleClock.secondsSinceLastInput()

        let newState: IdleState = idleSeconds >= Double(semiIdleThreshold) ? .semiIdle : .active
        idleState = newState

        guard let app = await MainActor.run(body: { NSWorkspace.shared.frontmostApplication }),
              let bundleID = app.bundleIdentifier else { return }

        let excludedApps = (try? await store.exclusions(kind: .app)) ?? []
        let excludedAppSet = Set(excludedApps)
        let appName = app.localizedName ?? bundleID
        guard !TreeBuilder.isAppExcluded(bundleID: bundleID, name: appName, excludedApps: excludedAppSet) else { return }

        let title = await MainActor.run { WindowTitleSampler.frontmostWindowTitle(for: app) }
        let tabURL = HierarchyBuilder.browserBundleIDs.contains(bundleID)
            ? await MainActor.run { BrowserTabInspector.activeTabURL(bundleID: bundleID) }
            : nil
        let chain = HierarchyBuilder.chain(bundleID: bundleID, appName: appName, windowTitle: title, tabURL: tabURL)

        do {
            var parentID: Int64?
            for level in chain {
                parentID = try await store.findOrCreateNode(
                    parentID: parentID, kind: level.kind, name: level.name,
                    bundleID: level.kind == .app ? bundleID : nil
                )
            }
            guard let leafNodeID = parentID else { return }

            if let open = openSession, open.nodeID != leafNodeID {
                try await store.recordSession(nodeID: open.nodeID, startedAt: open.start, endedAt: now)
                openSession = (leafNodeID, now)
            } else if openSession == nil {
                openSession = (leafNodeID, now)
            }

            try await store.addActiveSeconds(
                Int(elapsedSeconds.rounded()), isSemiIdle: newState == .semiIdle,
                keyClicks: 0, mouseClicks: 0, toNode: leafNodeID, day: now
            )
        } catch {
            AppLogger.tracking.error("failed to record sample: \(error)")
        }
    }

    private func flushOpenSession(endingAt end: Date) async throws {
        guard let open = openSession else { return }
        try await store.recordSession(nodeID: open.nodeID, startedAt: open.start, endedAt: end)
        openSession = nil
    }
}
