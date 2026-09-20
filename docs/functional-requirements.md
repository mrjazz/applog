# AppTracker — Current Functional Requirements

This document describes the behavior currently supported by the app. It is a product contract for the shipped implementation, not a roadmap.

## 1. Tracking

- The app samples the frontmost macOS application at a user-configurable interval (five seconds by default).
- A sample uses the app bundle identifier, display name, current window title when Accessibility access permits it, and the current time.
- Time is attributed to the frontmost app continuously while it can be sampled. Reading, watching video, and meetings without keyboard or mouse input count as screen time.
- The Input Activity setting records a separate semi-idle metric after no input for 10 seconds to 3 minutes, in 10-second increments. It does not remove time from screen-time totals.
- Historical totals are not recalculated when the no-input setting changes because the original per-sample idle timing is not retained.
- The app uses `CGEventSource.secondsSinceLastEventType` only to determine no-input duration. It does not capture keystroke content, mouse content, or request Input Monitoring permission.
- Time across a system sleep or an unusually delayed sampling tick is capped to prevent a single gap being over-credited.

## 2. Activity hierarchy

- General application titles are split on ` - `, ` | `, ` : `, ` > `, and `\\`; the application is the root and title parts become child nodes.
- Safari, Chrome, Firefox, Arc, and Microsoft Edge use a browser → domain → page-title hierarchy. Safari, Chrome, Arc, and Edge read the active-tab URL through their scripting support; Firefox falls back to a title-based domain guess.
- The app stores domains and page titles, not full URL paths.
- VS Code and supported JetBrains IDEs retain a project → tab hierarchy based on their title ordering.

## 3. Privacy

- All activity is stored locally in SQLite at `~/Library/Application Support/AppTracker/database.sqlite`.
- Adding an excluded app by bundle identifier or display name prevents future samples for that app from being stored. Existing data is hidden from Statistics while the exclusion is present.
- Adding an excluded domain prevents future samples for that domain and its subdomains from being stored. Existing matching data is hidden from Statistics while the exclusion is present.
- Exclusion changes update the Statistics tree, totals, and timeline immediately.
- The application has no network client or cloud synchronization.

## 4. Tags and Statistics

- Users can create tags with a name and color, rename a tag, and change its color by double-clicking its swatch.
- A selected tag can be applied to any selected tree node. Tags inherit through descendants unless a descendant has its own tag.
- The Statistics tree is ranked by tracked duration and supports expand/collapse, minimum-duration, name, date-range, and selected-tag filters. Filters combine.
- Each row shows its name, total duration, inherited tag state, and a duration-scaled tag-colored bar. Mixed descendants produce segmented bars.
- The toolbar shows today’s tracked time and, for a non-today range, the selected-range total.
- The Daily Timeline lists every day with recorded usage. Its 24-hour strips place completed and currently open sessions at their recorded times, use tag colors, and show quarter-day gridlines. Older data without session timing is shown as an aggregate fallback. Selecting a day reveals its per-category breakdown.

## 5. Application windows and menu bar

- Statistics is the main window. Settings opens in a separate window from the toolbar gear or the menu bar’s quick-action menu.
- A primary click on the menu bar icon opens or brings forward Statistics. A secondary click provides pause/resume, Statistics, Settings, and Quit actions.
- Tracking can be paused and resumed from Statistics or the menu-bar menu.
- Settings is one scrollable page with General, Input Activity, Storage, Privacy, Export, and About sections.
- Available General settings are launch at login, Dock visibility, sample interval, and a persisted menu-bar icon style selection.

## 6. Export

- Settings can export the currently filtered Statistics tree as a self-contained HTML report, CSV, or JSON.

## 7. Statistics shortcuts

<<<<<<< Updated upstream
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
- FR-23: All tracked data is stored locally in a SQLite database under `~/Library/Application Support/Applog/`. No data leaves the device.
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
- FR-32: **Database export**: exports a filtered subset of the raw database to a file that can later be merged into another Applog database; a companion **Merge** action combines an exported file into the current database.

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

(Remapped from the original Windows CTRL-based shortcuts to avoid conflicts with macOS system shortcuts.)

## 10. Non-Functional Requirements

- NFR-1: CPU usage while idle-sampling must be negligible (<1% average).
- NFR-2: Memory footprint target: comparable to source app's spirit — years of history stored in low tens of MB at most, using SQLite with periodic vacuum.
- NFR-3: The app must not crash-lose more than one sampling interval's worth of data on abnormal termination (power loss, force quit), given the autosave interval.
- NFR-4: Must run on the current and previous two macOS major versions (adjust per actual support policy at implementation time).
- NFR-5: Fully offline; sandboxed where feasible (Accessibility API access requires the app run outside the App Sandbox, or use of a helper — see design doc for tradeoffs).

