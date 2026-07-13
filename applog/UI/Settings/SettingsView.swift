import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Single scrollable page, no tabs (FR-33) — General, Idle & Away, Storage,
/// Privacy, and Export each get their own labeled section in order.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let store: Store
    @ObservedObject var statisticsViewModel: StatisticsViewModel

    @State private var excludedApps: [String] = []
    @State private var excludedDomains: [String] = []
    @State private var newExcludedApp = ""
    @State private var newExcludedDomain = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    generalSection
                    idleAwaySection
                    storageSection
                    privacySection
                    exportSection
                }
                .padding(28)
            }
        }
        .frame(width: 560, height: 620)
        .task { await loadExclusions() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(colors: [.gray, .gray.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 26, height: 26)
                .overlay(Image(systemName: "gearshape.fill").font(.system(size: 13)).foregroundStyle(.white))
            Text("Settings").font(.system(size: 15, weight: .semibold))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appToolbarBackground)
    }

    // MARK: General

    private var generalSection: some View {
        section(title: "General", color: .gray) {
            group {
                row(title: "Launch AppTracker at login", subtitle: "Starts automatically when you sign in") {
                    Toggle("", isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.setLaunchAtLogin($0) }
                    )).labelsHidden()
                }
                row(title: "Show in Dock", subtitle: "Also controls whether AppTracker appears in Cmd-Tab") {
                    Toggle("", isOn: Binding(
                        get: { settings.showInDock },
                        set: { settings.setShowInDock($0) }
                    )).labelsHidden()
                }
                row(title: "Sample frequency", subtitle: nil) {
                    Stepper(
                        "Every \(settings.sampleIntervalSeconds)s",
                        value: Binding(
                            get: { settings.sampleIntervalSeconds },
                            set: { settings.setSampleInterval(max(1, $0)) }
                        ), in: 1...60
                    )
                }
                row(title: "Menu bar icon", subtitle: "Clicking it always opens Statistics") {
                    Picker("", selection: Binding(
                        get: { settings.menuBarIconStyle },
                        set: { settings.setMenuBarIconStyle($0) }
                    )) {
                        ForEach(MenuBarIconStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
        }
    }

    // MARK: Idle & Away

    private var idleAwaySection: some View {
        section(title: "Idle & Away", color: .blue) {
            group {
                row(title: "Semi-idle after", subtitle: "Samples are flagged semi-idle below this") {
                    Stepper(
                        "\(settings.semiIdleThresholdSeconds)s",
                        value: Binding(
                            get: { settings.semiIdleThresholdSeconds },
                            set: { settings.setSemiIdleThreshold(max(1, $0)) }
                        ), in: 1...120
                    )
                }
                row(title: "Fully idle after", subtitle: "Sampling pauses; time accrues to Away") {
                    Stepper(
                        "\(settings.fullyIdleThresholdSeconds / 60)m",
                        value: Binding(
                            get: { settings.fullyIdleThresholdSeconds / 60 },
                            set: { settings.setFullyIdleThreshold(max(1, $0) * 60) }
                        ), in: 1...60
                    )
                }
                Text("When you come back, elapsed idle time is added to the \u{201C}Away\u{201D} node in Statistics automatically — no dialog interrupts you. Tag or rename it from the tree whenever you like.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
    }

    // MARK: Storage

    private var storageSection: some View {
        section(title: "Storage", color: .green) {
            group {
                row(title: "Autosave interval", subtitle: nil) {
                    Stepper(
                        "Every \(settings.autosaveIntervalMinutes)m",
                        value: Binding(
                            get: { settings.autosaveIntervalMinutes },
                            set: { settings.setAutosaveInterval(max(1, $0)) }
                        ), in: 1...60
                    )
                }
                row(title: "Keep backups", subtitle: nil) {
                    Stepper(
                        "Last \(settings.backupRetentionCount)",
                        value: Binding(
                            get: { settings.backupRetentionCount },
                            set: { settings.setBackupRetention(max(1, $0)) }
                        ), in: 1...50
                    )
                }
                row(title: "Cull items under", subtitle: "Folded into their parent node on load") {
                    Stepper(
                        "\(settings.cullThresholdSeconds)s · \(settings.cullAgeDays)d old",
                        value: Binding(
                            get: { settings.cullThresholdSeconds },
                            set: { settings.setCullThreshold(seconds: max(1, $0), ageDays: settings.cullAgeDays) }
                        ), in: 1...600, step: 10
                    )
                }
                row(title: "Database location", subtitle: nil) {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.databaseURL])
                    }
                }
            }
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
        section(title: "Privacy", color: .orange) {
            group {
                VStack(alignment: .leading, spacing: 8) {
                    Text("EXCLUDED APPS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.top, 12)
                    exclusionList(items: excludedApps) { value in
                        Task {
                            try? await store.removeExclusion(kind: .app, value: value)
                            await loadExclusions()
                        }
                    }
                    HStack {
                        TextField("Bundle identifier", text: $newExcludedApp)
                            .textFieldStyle(.roundedBorder)
                        Button("Add App…") {
                            guard !newExcludedApp.isEmpty else { return }
                            Task {
                                try? await store.addExclusion(kind: .app, value: newExcludedApp)
                                newExcludedApp = ""
                                await loadExclusions()
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 12)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("EXCLUDED DOMAINS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.top, 12)
                    exclusionList(items: excludedDomains) { value in
                        Task {
                            try? await store.removeExclusion(kind: .domain, value: value)
                            await loadExclusions()
                        }
                    }
                    HStack {
                        TextField("example.com", text: $newExcludedDomain)
                            .textFieldStyle(.roundedBorder)
                        Button("Add Domain…") {
                            guard !newExcludedDomain.isEmpty else { return }
                            Task {
                                try? await store.addExclusion(kind: .domain, value: newExcludedDomain)
                                newExcludedDomain = ""
                                await loadExclusions()
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 12)
                }
            }
        }
    }

    private func exclusionList(items: [String], onRemove: @escaping (String) -> Void) -> some View {
        VStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                HStack {
                    Text(item).font(.system(size: 12.5))
                    Spacer()
                    Button {
                        onRemove(item)
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                Divider().padding(.leading, 16)
            }
        }
    }

    // MARK: Export

    private var exportSection: some View {
        section(title: "Export", color: .pink) {
            group {
                row(title: "HTML Report", subtitle: "A shareable, self-contained page of the current Statistics filters") {
                    Button("Export HTML…") { exportHTML() }
                        .buttonStyle(.borderedProminent)
                }
                row(title: "CSV / JSON", subtitle: "Structured data for spreadsheets or other tools") {
                    HStack {
                        Button("Export CSV…") { exportCSV() }
                        Button("Export JSON…") { exportJSON() }
                    }
                }
                row(title: "Export Database", subtitle: "Save the currently filtered subset for merging on another Mac") {
                    Button("Export…") { }
                }
                row(title: "Merge Database", subtitle: "Combine an exported database file into this one") {
                    Button("Merge…") { }
                }
            }
        }
    }

    // MARK: Actions

    private func loadExclusions() async {
        excludedApps = (try? await store.exclusions(kind: .app)) ?? []
        excludedDomains = (try? await store.exclusions(kind: .domain)) ?? []
    }

    private func exportHTML() {
        save(suggestedName: "AppTracker Report.html", contentType: .html) {
            ExportService.html(rows: statisticsViewModel.rows)
        }
    }

    private func exportCSV() {
        save(suggestedName: "AppTracker Export.csv", contentType: .commaSeparatedText) {
            ExportService.csv(rows: statisticsViewModel.rows)
        }
    }

    private func exportJSON() {
        save(suggestedName: "AppTracker Export.json", contentType: .json) {
            ExportService.json(rows: statisticsViewModel.rows)
        }
    }

    private func save(suggestedName: String, contentType: UTType, content: () -> String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [contentType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? content().write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Layout helpers

    private func section<Content: View>(title: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 7, height: 7)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
            }
            content()
        }
    }

    private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }

    private func row<Content: View>(title: String, subtitle: String?, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Divider() }
    }
}
