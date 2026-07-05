# AppTracker — macOS App Design

Companion to [functional-requirements.md](./functional-requirements.md). Describes the technical architecture for implementing AppTracker as a native Swift/SwiftUI macOS app.

## 1. Platform & Stack

- **Language**: Swift 6
- **UI**: SwiftUI for Settings and Statistics windows; `NSStatusItem` (AppKit, via `NSApplicationDelegateAdaptor`) for the menu bar item, since SwiftUI's `MenuBarExtra` is usable here too (macOS 13+) — prefer `MenuBarExtra` unless custom icon-state rendering demands raw AppKit.
- **Persistence**: SQLite via [GRDB.swift](https://github.com/groue/GRDB.swift) — chosen over Core Data because the data model is simple (append-only samples + a mutable tag/node tree) and GRDB gives direct control over compaction, vacuuming, and merge/export SQL.
- **Minimum target**: macOS 13 (Ventura) — enables `MenuBarExtra` and `SMAppService` for launch-at-login.
- **Distribution**: Direct download (notarized, non-App-Store) is recommended for v1, because Accessibility API usage and system-wide window title reading are incompatible with the App Sandbox. A sandboxed App Store variant is a possible future path with reduced tracking fidelity (see §7).

## 2. High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│  AppTrackerApp (SwiftUI App)                             │
│  ├─ MenuBarExtra (status item; click opens Statistics)    │
│  ├─ StatisticsWindow (SwiftUI, tree + filters)             │
│  └─ SettingsWindow (SwiftUI)                               │
└─────────────────────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────┐
│  TrackingEngine (actor)                                   │
│  - Timer-driven sampler (default 5s)                      │
│  - Idle/away state machine                                │
│  - Delegates to Samplers, writes via Store                │
└─────────────────────────────────────────────────────────┘
     │                    │                     │
     ▼                    ▼                     ▼
┌───────────┐     ┌───────────────┐    ┌──────────────────┐
│FrontmostApp│     │WindowTitle    │    │IdleClock          │
│Sampler     │     │Sampler (AX)   │    │(CGEventSource)     │
│(NSWorkspace)│     │+ BrowserURL   │    │                    │
└───────────┘     │  Sampler (AX/  │    └──────────────────┘
                   │  AppleScript) │
                   └───────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────┐
│  Store (GRDB DatabaseQueue wrapper)                       │
│  - Tree model (Node table, adjacency list)                 │
│  - Samples aggregated into per-node duration counters      │
│  - Tags, exclusions, settings                              │
│  - Autosave / backup / cull / merge / export operations    │
└─────────────────────────────────────────────────────────┘
```

## 3. Tracking Pipeline

### 3.1 Sampler protocol

```swift
protocol Sampler {
    func sample() async -> SampleResult?
}

struct SampleResult {
    let bundleID: String
    let appName: String
    let windowTitle: String?
    let domain: String?       // only for recognized browsers
    let timestamp: Date
}
```

- `FrontmostAppSampler` uses `NSWorkspace.shared.frontmostApplication`.
- `WindowTitleSampler` uses the Accessibility API (`AXUIElementCopyAttributeValue` on the frontmost app's focused window, `kAXTitleAttribute`) to read the window title of *other* processes. Requires the app be Accessibility-trusted (`AXIsProcessTrusted()`); if untrusted, prompts via `AXIsProcessTrustedWithOptions` with the "prompt" option, then deep-links to System Settings → Privacy & Security → Accessibility.
  - This sampler is intentionally app-agnostic (FR-3): it never enumerates an app's tabs/documents/windows. It only ever reads the *frontmost* window's title at each tick and hands that string to the generic delimiter parser in `Store`. A Terminal tab, a Mail message, or a Notes document each produce their own child node purely because their titles differ and each becomes frontmost at some point — the per-document hierarchy is an emergent property of sampling-over-time plus delimiter parsing, not a per-app integration. No special-casing is needed for Terminal, Mail, Notes, or similar apps; only browsers get bespoke handling (below), because grouping by domain is materially more useful there than raw title parsing would be.
- `BrowserURLSampler` special-cases Safari, Chrome, Arc, Edge, Firefox and produces the fixed three-level hierarchy from FR-4 (browser → domain → page title):
  - Safari/Chrome/Arc/Edge (Chromium + WebKit apps expose scripting dictionaries): use `NSAppleScript`/`osascript`-equivalent via the Scripting Bridge to read the active tab's URL and title directly — more reliable than title-parsing alone, and works even when the visible window title doesn't include the full domain.
  - Firefox has no public scripting API; fall back to parsing the window title only, still producing the same three-level shape on a best-effort basis (domain extracted from the title string where possible).
  - The domain (`host` component) becomes the second-level node; the tab's exact title becomes the third-level node. No full URL/path is stored (privacy — see FR-36).

### 3.2 TrackingEngine loop

`TrackingEngine` is a Swift `actor` owning a `DispatchSourceTimer` at the configured sample interval. Each tick:

1. Read last-input timestamp: `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .init(rawValue: ~0)!)`.
2. Compute idle state: `active` / `semiIdle` / `fullyIdle` against configured thresholds.
3. If `fullyIdle`, skip sampling entirely (no app attribution) but keep an in-memory counter of elapsed idle seconds.
4. When input resumes (`fullyIdle` → `active`), flush the accumulated idle duration silently into the synthetic root-level **"Away"** node's `usage_bucket` for the current day — no dialog, no main-actor UI interruption, no pause. The engine simply resumes sampling immediately (FR-7).
5. Otherwise run the sampler chain, build a `SampleResult`, and hand it to `Store.recordSample(_:isSemiIdle:)`.

### 3.3 Idle thresholds

Config values live in `Settings` (see §6), all in seconds:
`sampleInterval = 5`, `semiIdleThreshold = 10`, `fullyIdleThreshold = 180` — matching FR-5/FR-6. There is no separate "away" threshold or dialog: any fully-idle span, once it ends, becomes Away time (FR-7).

## 4. Data Model

### 4.1 Tables (GRDB / SQLite)

```
node(
  id INTEGER PRIMARY KEY,
  parent_id INTEGER REFERENCES node(id),
  kind TEXT,            -- 'app' | 'title-segment' | 'domain' | 'page-title' | 'away'
  name TEXT NOT NULL,
  bundle_id TEXT,        -- set on 'app' nodes
  tag_id INTEGER REFERENCES tag(id),   -- explicit override, nullable
  hidden BOOLEAN DEFAULT 0,
  created_at DATETIME,
  UNIQUE(parent_id, kind, name)
)

usage_bucket(
  node_id INTEGER REFERENCES node(id),
  day DATE NOT NULL,               -- calendar day, local time
  active_seconds INTEGER DEFAULT 0,
  semi_idle_seconds INTEGER DEFAULT 0,
  key_clicks INTEGER DEFAULT 0,
  mouse_clicks INTEGER DEFAULT 0,
  PRIMARY KEY (node_id, day)
)

session(
  id INTEGER PRIMARY KEY,
  node_id INTEGER REFERENCES node(id),
  started_at DATETIME NOT NULL,     -- exact start, used to place the block on the daily timeline
  ended_at DATETIME NOT NULL
)

tag(
  id INTEGER PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  color TEXT NOT NULL       -- hex
)

setting(key TEXT PRIMARY KEY, value TEXT)

exclusion(kind TEXT, value TEXT, PRIMARY KEY(kind, value))  -- kind = 'app' | 'domain'
```

- Samples are aggregated into two places, not stored individually:
  - `usage_bucket` rows keyed by `(node_id, day)` hold the running totals the tree and tag counts read from — this bounds that table's growth to (nodes × days) instead of (nodes × days × 17280 samples/day), which is what keeps the on-disk size small (mirrors the source app's "years of data in under 100KB" goal, FR/NFR-2).
  - `session` rows record each contiguous span of consecutive samples for the same node (start/end timestamp), coalesced in-memory by `TrackingEngine` and flushed as one row whenever the frontmost node changes or idle begins — not one row per 5-second tick. This is the minimum needed to place a block of time at a specific hour for the daily timeline panel (FR-19b); `usage_bucket` alone only has a day total, with no notion of *when in the day* it happened.
  - Both tables are written in the same transaction per flush, so they never drift apart. `session` rows older than the cull age (FR-26) are pruned once their contribution is already folded into `usage_bucket`/the parent node — only the totals need to survive long-term, not the exact minute-by-minute history, so `session` stays bounded to recent data rather than growing forever.
- Hierarchy is a plain adjacency list (`parent_id`), walked recursively (SQLite `WITH RECURSIVE`) to build the tree for the Statistics view and for merge/cull operations.
- Tag inheritance (FR-12/FR-13) is resolved at query time: walk up `parent_id` until a non-null `tag_id` is found, defaulting to "Untagged".
- **Away time** (FR-7) has no dedicated table. A single root-level node `(parent_id = NULL, kind = 'away', name = 'Away')` is created lazily on first use; idle spans are flushed straight into its `usage_bucket` rows, same as any tracked app. This is what keeps the "quiet" behavior simple: there is no separate away-categorization workflow to build, store, or reconcile — it's just another node the user can tag or rename whenever they choose to look at it.

### 4.2 Compaction

- **Culling** (FR-26): a maintenance pass (on launch, and optionally nightly) finds leaf nodes whose total `active_seconds` across all buckets is below `cullThresholdSeconds` and whose most recent bucket `day` is older than `cullAgeDays`; it adds their bucket rows into the parent node's buckets (by day) and deletes the leaf.
- **Vacuum**: `PRAGMA auto_vacuum = INCREMENTAL` plus a periodic `PRAGMA incremental_vacuum` after large deletes (culls/merges).

## 5. Statistics View (SwiftUI)

- Three-column layout: left sidebar = filter controls (minimum-duration field, name-contains search field, date range fields + Quick Set dropdown, and the Tags list); center = `OutlineGroup`/`List` tree bound to a `TreeViewModel` that recomputes visible rows from the filter state; right = the daily timeline panel (below).
- **Tags list** is a single-select `List` (not checkboxes): the highlighted row is the "active" tag. Below it, two buttons — **Apply Tag to Node** (assigns the active tag to whatever tree node is currently selected, FR-19) and **Rename Tag** (FR-14b) — plus a **"Filter on selected tag"** checkbox that, when on, restricts the tree to nodes resolving to the active tag.
- Each tree row: `HStack` with icon, name, duration label, and a bar drawn via `Canvas`. Bar **length** is normalized against the largest duration among currently visible rows (so length reads as absolute magnitude across the whole tree, not just within a subtree). Bar **color** is a single fill for single-tag nodes, or a stacked/segmented fill — one colored segment per tag, sized by that tag's share of the node's total time — for nodes whose descendants carry more than one tag. Segment proportions are computed from descendant `usage_bucket` sums grouped by resolved tag.
- Browser nodes render at three fixed levels (browser → domain → page title, FR-4); non-browser apps render at whatever depth their delimiter-parsed titles produce (FR-3). Any level, at any depth, can be the target of Apply Tag.
- Selection-driven actions (Apply Tag, Hide/Unhide, Merge, Manual Edit) are bound to the keyboard shortcuts in FR §10, implemented via SwiftUI `.keyboardShortcut(_:modifiers:)`.
- Filtering is pure (no DB writes); it operates on a snapshot fetched via a GRDB `ValueObservation` so the tree updates live as new samples land while the window is open.
- **Daily timeline panel** (FR-19b): one row per calendar day, each a `Canvas`-drawn 24-hour strip. For a given day, the strip is built from that day's `session` rows (§4.1) across *all* nodes — each session's `started_at`/`ended_at` places a colored block directly on the hour axis, resolved to its node's tag. Gaps (no session covering that time) render in the neutral untagged color, representing fully-idle/away spans. This panel scrolls independently of the tree and is unaffected by the tree's filters — it always shows full days.
- The toolbar carries a single **Settings** button (gear glyph) that opens the Settings window (FR-19a). There is no Export control here — Statistics stays scoped to browsing and tagging; export moved to Settings (§8).

## 6. Settings

- Statistics is the app's one `WindowGroup` main window (FR-20); Settings is a **separate SwiftUI `Window` scene**, opened via `openWindow(id: "settings")` from the Statistics toolbar's gear button, rather than the standard `Settings` scene (`⌘,`) — this keeps a visible, addressable window rather than the OS-managed singleton Preferences panel, since users open it by clicking, not via the app menu.
- **Single scrollable page, not tabs** (FR-33): a `ScrollView` containing five labeled sections in order — **General**, **Idle & Away**, **Storage**, **Privacy**, **Export** — each its own `VStack` under a small caption-style heading, matching the grouped-rows look used throughout (§5). There is no `TabView` and no per-section navigation; everything is visible by scrolling. The "Idle & Away" section only exposes the semi-idle and fully-idle thresholds plus an explanatory note — there is no away-dialog or category configuration, since Away time is recorded silently (FR-7). The **Export** section hosts everything from FR-30–FR-32 (HTML/CSV/JSON export, database export/merge) — see §8.
- Backed by a `Settings` struct persisted as key/value rows in the `setting` table (not `UserDefaults`, so settings travel with database export/merge/restore). A thin `UserDefaults`-like accessor wraps it for ergonomics.
- Launch-at-login via `SMAppService.mainApp.register()/unregister()` (macOS 13+ API, replaces `SMLoginItemSetEnabled`).

## 7. Permissions Strategy

- Accessibility permission is mandatory for cross-process window title reads; this rules out the App Sandbox for v1 (sandboxed apps cannot call `AXUIElementCopyAttributeValue` on arbitrary other processes). The app therefore ships outside the sandbox, notarized via Developer ID.
- No Input Monitoring entitlement is requested: idle detection only needs the aggregate "seconds since last input" value (`CGEventSource`), which does not require that permission — this must be re-verified against the current macOS SDK during implementation, since Apple has tightened these APIs across releases.
- A future App Store-compatible variant could drop live window-title reading and rely solely on `NSWorkspace` frontmost-app notifications (app-level granularity only, no document/site hierarchy) as a reduced-fidelity fallback — noted here as a design option, not committed for v1.

## 8. Export

Export lives entirely in the Settings → Export tab (§6), not in the Statistics toolbar.

- **HTML**: a Swift `Codable`→`String` templating step renders the currently filtered tree into a static HTML file (inline CSS, no external assets) via `String` templates; mirrors FR-30 (filters applied, cull/expansion state not applied to the export tree — export always renders full depth of the filtered set).
- **CSV/JSON**: straightforward `Encodable` dump of the same filtered node list (FR-31).
- **Database export/merge**: exports a filtered subgraph (matching nodes + their ancestors, to preserve hierarchy) into a standalone SQLite file with the same schema; merge reads a foreign database, matches nodes by `(parent path, kind, name)`, and sums `usage_bucket` rows, creating nodes that don't yet exist (FR-27).

## 9. Backups & Crash Recovery

- Autosave: GRDB write transactions already commit per-sample-batch; "autosave" in practice means periodic `PRAGMA wal_checkpoint(TRUNCATE)` on the configured interval (default 10 min) to keep the WAL file bounded and the main DB file consistent on disk (FR-24).
- Backups: on each checkpoint, copy the DB file to `~/Library/Application Support/AppTracker/Backups/checkpoint-<timestamp>.sqlite`, retaining the last N (configurable, e.g., 10) plus one per calendar day for M days — pruned on each backup (FR-25).
- Corruption recovery: on launch, run `PRAGMA integrity_check`; if it fails, present a dialog offering to restore from the most recent valid backup before continuing.

## 10. Menu Bar

- `MenuBarExtra(content:label:)` with `.menuBarExtraStyle(.window)` rather than `.menu` — a "window" style extra reacts to a primary click by running arbitrary code (opening/focusing the Statistics window via `openWindow(id: "statistics")` + `NSApp.activate`) instead of showing a menu, which is what makes "click always opens Statistics" possible (FR-21). Label icon swaps between active/paused/idle glyphs (SF Symbols: `circle.fill`, `pause.circle`, `moon.zzz` or similar) per FR-22.
- A secondary (right) click shows a small `NSMenu` — built directly via `NSStatusItem.menu` alongside the `MenuBarExtra`, or via a right-click gesture recognizer — with **Start/Pause Tracking**, **Settings…** (`openWindow(id: "settings")`), and **Quit** (FR-21a). Statistics itself stays off this menu — a plain click is the only way to it (FR-21) — but Settings is duplicated here as a convenience for reaching it without bringing Statistics forward first.

## 11. Testing Strategy

- Unit tests for: title-parsing/delimiter logic, tag-inheritance resolution, idle state machine transitions, cull/merge SQL correctness — all pure/DB logic, no UI or Accessibility dependency, so fully testable in CI.
- Accessibility- and NSWorkspace-dependent samplers are covered by protocol abstraction (`Sampler`) with fakes in tests; real integration is verified manually (see project's `/run` or `/verify` skill once implementation exists).

## 12. Open Questions / Decisions Deferred to Implementation

- Exact SF Symbol set and icon design for menu bar states.
- Whether hourly-resolution usage buckets are worth adding later for finer time-of-day reporting (v1 uses daily buckets only, per §4.2).
- Firefox domain extraction fidelity given no scripting API — may need a companion browser extension in a future version; out of scope for v1 (title-parsing fallback only).
