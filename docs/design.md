# AppTracker — Current Technical Design

Companion to [functional-requirements.md](./functional-requirements.md). This describes the architecture that exists in the app today.

## Architecture

The app is a native SwiftUI macOS application. `AppEnvironment` creates and shares one `Store`, `SettingsStore`, `TrackingEngine`, and `StatisticsViewModel` between the Statistics window, Settings window, and AppKit menu-bar delegate.

- `TrackingEngine` is an actor that runs the sampling loop.
- `Store` is an actor wrapping a single SQLite connection and serializing reads and writes.
- `StatisticsViewModel` owns Statistics filters and creates display rows from a snapshot of nodes, tags, usage buckets, and exclusions.
- SwiftUI views remain lightweight; Settings and Statistics delegate persistence and calculations to these objects.

## Tracking pipeline

1. `NSWorkspace.shared.frontmostApplication` provides the active app.
2. `WindowTitleSampler` reads the focused window title through Accessibility where permission is available.
3. `IdleClock` reads the aggregate system-wide time since the latest input event. This creates a semi-idle marker only; it never stops attribution or moves time to an Away category.
4. `HierarchyBuilder` creates an app/title hierarchy. Supported browsers use browser → domain → page-title; Safari, Chrome, Arc, and Edge obtain their active URL through AppleScript, while Firefox uses a best-effort title fallback.
5. Before persistence, app and domain exclusions are checked. A matching app, domain, or subdomain is not written.
6. The elapsed interval is written to the current leaf node. `active_seconds` always receives screen time; `semi_idle_seconds` receives the same interval only when the no-input threshold is reached.

The engine starts a session when a node becomes active and flushes it when the active node changes or tracking is paused. An in-memory open session is also exposed to Statistics so today’s timeline can render before the node changes.

## Persistence

SQLite is stored at `~/Library/Application Support/AppTracker/database.sqlite`, using WAL mode and foreign keys.

| Table | Purpose |
| --- | --- |
| `node` | Activity hierarchy, tag assignment, and hidden-state field. |
| `usage_bucket` | Per-node/per-day active, semi-idle, keyboard, and mouse counters. Keyboard and mouse counters are currently always zero. |
| `session` | Completed contiguous node spans for the daily timeline. |
| `tag` | User-defined names and hexadecimal colors. |
| `setting` | Persisted preference values. |
| `exclusion` | App and domain exclusions. |

Raw samples are intentionally not retained. This keeps the database compact but means an earlier no-input threshold cannot be applied retroactively.

## Statistics

`TreeBuilder` constructs a recursive tree from the node graph and day buckets. It resolves tag inheritance while calculating row totals and segmented tag bars. App and domain exclusions are applied consistently to the tree, totals, and timeline.

The daily timeline reads all recorded usage days, then uses `session` start/end times to place colored tag blocks on a 24-hour strip. For older database rows without session data, it falls back to aggregate tag segments so no recorded day disappears. The selected row shows the category totals for that day.

## Settings and menu bar

Settings is a separate SwiftUI window with a single scrollable page. Preferences are written asynchronously to `setting` rows. Exclusion changes explicitly refresh `StatisticsViewModel` so their effect is immediate.

`AppDelegate` owns an `NSStatusItem` to distinguish primary and secondary clicks. Primary click opens Statistics; secondary click opens a quick-action menu. The status icon currently distinguishes paused from recording states.

## Permissions and privacy

Accessibility permission is used for cross-process window titles. The app does not request Input Monitoring because it reads only the system’s aggregate last-input time; no event content is captured. Browser scripting may require macOS automation approval for the corresponding browser.

## Node editing and shortcuts

The Statistics window installs a local key-event monitor while visible. It ignores events routed to a text editor, then maps the documented shortcuts to the selected node. Manual correction writes a positive or negative `active_seconds` adjustment to today’s bucket. Hiding updates the node’s `hidden` flag. Merging folds all buckets in the source subtree into the target node and removes the source subtree and its completed session rows.

## Not implemented

The schema and Settings UI reserve space for backup retention, autosave/checkpoint scheduling, culling, database export/merge, and alternate menu-bar icon styles. Those capabilities are not wired into the current runtime behavior.
