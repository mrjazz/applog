# AppTracker — Functional Requirements Specification

Source concept: [ProcrastiTracker](http://strlen.com/procrastitracker) (Windows). This document adapts that concept into a native macOS application, replacing Windows-specific mechanisms (system tray, Win32 hooks, custom binary database) with macOS equivalents (menu bar, Accessibility API, SQLite).

## 1. Purpose

AppTracker automatically monitors which applications, documents, and websites the user is actively using, and for how long, without requiring manual timers. It lets the user analyze their own usage patterns after the fact, tag time for billing/project purposes, and export reports — all from a lightweight menu bar app.

## 2. Core Tracking Behavior

### 2.1 Sampling
- FR-1: The app samples the frontmost application and its active window title on a timer, default interval **5 seconds**, user-configurable.
- FR-2: Each sample records: app bundle identifier, app display name, window title (if obtainable), timestamp, and whether the sample was "active" or "idle".

### 2.2 Per-document / per-tab tracking

The guiding rule: **any distinct "thing" a process shows the user — a tab, a document, a conversation, a window — is tracked and displayed as its own node**, not folded into a single entry for the whole app. This applies uniformly; there is no fixed allow-list of "trackable" apps.

- FR-3: For general apps, window titles are parsed into a hierarchy by splitting on common delimiters: ` - `, ` | `, ` : `, ` > `, `\`. The app name is the root node; parsed title segments become child nodes (arbitrary depth). Because the sampler records whatever title is frontmost at each tick, every tab/document a user visits — across any number of tabs or windows in that app — accumulates its own node over time, keyed by its distinct title text. Examples this covers without any app-specific code:
  - **Terminal / iTerm**: each shell tab (e.g. distinguished by working directory or running process in the title) is its own child node.
  - **Mail**: each open message or selected mailbox is its own child node.
  - **Notes**: each note is its own child node.
  - **Xcode**: each open file is its own child node.
  - **Slack**: each channel/DM is its own child node.
- FR-4: For known web browsers (Safari, Chrome, Firefox, Arc, Edge), the app builds a **fixed three-level hierarchy** instead of generic delimiter parsing, since a domain-level grouping is more useful than raw title parsing would produce:
  1. **Browser** (root) — e.g. Safari
  2. **Domain** — e.g. `github.com`
  3. **Page title** — the exact title of the active tab, e.g. "mrjazz/apptracker — Pull Request #42"

  Domain and page title are read via the Accessibility API and, where available, Safari/Chrome scripting bridges, rather than parsed from the title string. Each of the three levels can independently be tagged.
- FR-4a: Because sampling only observes the frontmost window/tab at each tick, an app with several tabs/documents open simultaneously builds up its full set of child nodes gradually, as the user switches between them — no enumeration of background/inactive tabs is required or attempted.

### 2.3 Idle & away detection
- FR-5: **Semi-idle**: no keyboard/mouse input for a configurable threshold (default 10s). Sampling continues but the sample is flagged semi-idle.
- FR-6: **Fully idle**: no input for a configurable threshold (default 3 minutes). Data collection halts; elapsed idle time is not attributed to any tracked app.
- FR-7: **Away (silent)**: once input resumes after a fully-idle span, the elapsed idle duration is automatically attributed to a dedicated **"Away" node** at the root of the statistics tree — no dialog, prompt, or interruption is shown. The app stays quiet. The Away node behaves like any other node: it can be renamed, tagged, hidden, or merged, so the user can categorize elapsed away-time later, on their own schedule, directly from the Statistics view.
- FR-8: Idle detection uses system-wide last-input timestamp (`CGEventSource.secondsSinceLastEventType`), not app-specific hooks.

### 2.4 Input activity counts
- FR-9: The app counts keyboard presses and mouse clicks (not content) per sampling interval, attributed to the active app/window node, for engagement-intensity display. Exact keystrokes/text are never captured.

## 3. Tagging

- FR-10: Users can create custom tags (name + color) to represent projects/categories.
- FR-11: Tags can be applied to any tree node — app, document, or, for browsers, any of the three levels (browser, domain, or page title).
- FR-12: A tag applied to a parent node propagates to all descendant nodes unless a descendant has its own explicit tag override.
- FR-13: Untagged nodes display as "Untagged" and inherit the nearest tagged ancestor for reporting/filtering purposes.
- FR-14: The statistics view color-codes usage bars by tag; nodes with mixed child tags show a subdivided/stacked bar.
- FR-14a: Tag selection is single-select (one active tag at a time), not checkboxes — the selected tag is the target for "Apply Tag to Node" and, when "Filter on selected tag" is checked, restricts the visible tree to nodes resolving to that tag.
- FR-14b: A "Rename Tag" action renames the currently selected tag in place; the new label is reflected everywhere the tag is used.

## 4. Statistics View

- FR-15: A hierarchical tree view lists tracked apps/documents/sites/pages ranked by total active time (descending), each expandable to reveal children ordered the same way.
- FR-16: Each row shows: name, total duration, and a **horizontal bar to the right of the duration**. The bar's length is scaled relative to the largest visible node's duration (so length communicates relative magnitude, not just proportion-of-parent). If the node's accumulated time spans more than one tag (via its descendants), the bar is subdivided into colored segments — one per tag — sized in proportion to that tag's share of the node's total time. A single-tag (or untagged) node renders as one solid-colored segment.
- FR-17: Filter controls, in the left sidebar:
  - Minimum-duration threshold (hide items under N minutes)
  - Name-contains / substring search
  - Date range (explicit from/to fields plus a Quick Set dropdown: Today, This Week, This Month, All Time, Custom Range)
  - Tags list (single-select — see FR-14a) with a separate "Filter on selected tag" checkbox
- FR-18: Filters combine (AND) and update the tree live.
- FR-19: An **"Apply Tag to Node"** button in the sidebar assigns the tag currently selected in the Tags list to the currently selected tree node(s). A **"Rename Tag"** button renames the selected tag (FR-14b).
- FR-19a: The Statistics toolbar includes a **Settings button** (gear icon) that opens the Settings window. There is no separate Export button in Statistics — export lives in Settings (see §7).
- FR-19b: A third panel, to the right of the tree, shows a **daily timeline**: one horizontal row per calendar day (most recent at top), spanning a fixed 24-hour axis (midnight to midnight) with hour gridlines at 6h intervals. Each row is filled with colored segments — using the same tag colors as the tree — showing what was being tracked at each point in that day, so daily rhythm and idle/away stretches are visible at a glance across many days at once. This panel is independent of the tree's expand/collapse state; it always reflects the full day regardless of which tree nodes are visible.

## 5. Menu Bar Presence

- FR-20: The app runs as a menu bar (status item) app with no Dock icon by default (configurable to show in Dock). **Statistics is the app's one main window** — there is no separate "home" screen.
- FR-21: Clicking the menu bar icon always opens (or brings forward) the Statistics window directly. There is no dropdown menu on click — nothing else can happen when the icon is clicked.
- FR-21a: Right-clicking the menu bar icon offers a minimal quick-action menu — **Start/Pause Tracking**, **Settings…**, and **Quit** — for the actions a user might want without bringing the Statistics window forward. This is a convenience shortcut; Statistics itself is still only opened via a plain click (FR-21).
- FR-22: The menu bar icon visually indicates tracking state (active / paused / idle).

## 6. Data Management

### 6.1 Storage
- FR-23: All tracked data is stored locally in a SQLite database under `~/Library/Application Support/AppTracker/`. No data leaves the device.
- FR-24: The database auto-saves/checkpoints on a configurable interval (default 10 minutes) and on graceful quit.
- FR-25: The app keeps rolling backups (e.g., last N daily snapshots) to recover from corruption; on launch, if the primary database is unreadable, the app offers to restore from the most recent backup.

### 6.2 Culling
- FR-26: On load (or on a scheduled maintenance pass), items below a configurable age+duration threshold are "culled": their accumulated time is folded into their parent node and the leaf is removed, keeping the database compact.

### 6.3 Merging
- FR-27: Users can merge one tree node into another (combining accumulated time), merge sibling nodes matching a substring, or merge an entire external database file into the current one (for combining data from multiple Macs).

### 6.4 Editing
- FR-28: Users can manually add/adjust minutes on a node (manual correction mode) for cases where tracking missed time (e.g., app was quit during use).
- FR-29: Users can hide a node (it keeps accumulating time in the background but is not shown in the tree) and unhide it later.

## 7. Export

Export lives in the **Export** section of Settings (FR-33), not in the Statistics toolbar, so Statistics stays focused on browsing and tagging data.

- FR-30: **HTML export**: generates a self-contained, readable HTML report of the currently filtered statistics tree (respects seconds/tag/date/search filters), suitable for sharing.
- FR-31: **CSV/JSON export**: exports the filtered tree as structured data for use in spreadsheets or other tools.
- FR-32: **Database export**: exports a filtered subset of the raw database to a file that can later be merged into another AppTracker database; a companion **Merge** action combines an exported file into the current database.

## 8. Settings

- FR-33: Settings is a **single scrollable window** (opened via the gear button in Statistics, FR-19a) — not a tabbed interface. All sections appear on one page, each under its own labeled heading, in this order:
  - **General**: launch at login, show in Dock, sample frequency, menu bar icon appearance
  - **Idle & Away**: semi-idle threshold, fully-idle threshold (no away-dialog configuration — see FR-7)
  - **Storage**: autosave interval, backup retention count, cull threshold, "Show Database in Finder", "Restore from Backup…"
  - **Privacy**: excluded apps (never tracked), excluded browser domains, each with an "Add…" action
  - **Export**: HTML/CSV/JSON export and database export/merge (FR-30–FR-32)

## 9. Permissions & Privacy

- FR-34: The app requires **Accessibility** permission (to read window titles/URLs of other apps) and **Input Monitoring** permission is NOT required if idle detection uses only `CGEventSource` global timestamps (no keystroke content read); this must be verified during implementation and the request scoped to the minimum needed.
- FR-35: On first launch, the app explains why Accessibility access is requested and deep-links to System Settings.
- FR-36: Users can add apps/domains to an exclusion list; excluded items are never sampled or stored.
- FR-37: No tracked data is transmitted off-device; there is no network component.

## 10. Keyboard Shortcuts (Statistics window)

| Shortcut | Action |
|---|---|
| `T` | Apply currently selected tag to selected node |
| `⌘⇧H` | Hide selected node |
| `⌘⇧U` | Unhide nodes below selected node |
| `⌘⇧M` | Merge selected node into a chosen target node |
| `⌘⇧P` | Merge sibling nodes matching selected node's name as substring |
| `⌘E` | Enter manual time-correction mode for selected node |

(Remapped from the original Windows CTRL-based shortcuts to avoid conflicts with macOS system shortcuts.)

## 11. Non-Functional Requirements

- NFR-1: CPU usage while idle-sampling must be negligible (<1% average).
- NFR-2: Memory footprint target: comparable to source app's spirit — years of history stored in low tens of MB at most, using SQLite with periodic vacuum.
- NFR-3: The app must not crash-lose more than one sampling interval's worth of data on abnormal termination (power loss, force quit), given the autosave interval.
- NFR-4: Must run on the current and previous two macOS major versions (adjust per actual support policy at implementation time).
- NFR-5: Fully offline; sandboxed where feasible (Accessibility API access requires the app run outside the App Sandbox, or use of a helper — see design doc for tradeoffs).

## 12. Out of Scope (v1)

- Cloud sync / multi-device live sync (manual database export/merge covers cross-device use).
- Team/shared reporting or billing integrations.
- Mobile companion app.
- Automatic detection of meeting attendance beyond app/window sampling.
