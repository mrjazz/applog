import SwiftUI

struct StatisticsView: View {
    @ObservedObject var viewModel: StatisticsViewModel
    @ObservedObject var permissions: PermissionsMonitor
    let isPaused: Bool
    let onTogglePause: () -> Void
    @Environment(\.openWindow) private var openWindow
    @State private var showPermissionBanner = true
    @State private var isSidebarCollapsed = false
    @State private var isTimelineCollapsed = false

    var body: some View {
        mainContent
            .frame(minWidth: 920, minHeight: 560)
            .overlay(alignment: .top) { bannerOverlay }
            .task { await viewModel.refresh() }
            .onChange(of: viewModel.minDurationMinutes) { refreshOnChange() }
            .onChange(of: viewModel.searchText) { refreshOnChange() }
            .onChange(of: viewModel.quickSet) { refreshOnChange() }
            .onChange(of: viewModel.customFrom) { refreshOnChange() }
            .onChange(of: viewModel.customTo) { refreshOnChange() }
            .onChange(of: viewModel.filterOnTag) { refreshOnChange() }
            .onChange(of: viewModel.selectedTagID) { refreshOnChange() }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                if !isSidebarCollapsed {
                    FilterSidebar(viewModel: viewModel)
                    Divider()
                }
                TreeListView(
                    rows: viewModel.rows, maxSeconds: viewModel.maxRowSeconds,
                    selectedNodeID: $viewModel.selectedNodeID, expandedNodeIDs: $viewModel.expandedNodeIDs
                )
                    .frame(maxWidth: .infinity)
                if !isTimelineCollapsed {
                    Divider()
                    TimelinePanel(days: viewModel.timelineDays, tags: viewModel.tags)
                        .frame(width: 240)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isSidebarCollapsed)
            .animation(.easeInOut(duration: 0.18), value: isTimelineCollapsed)
        }
    }

    @ViewBuilder
    private var bannerOverlay: some View {
        if shouldShowPermissionBanner {
            PermissionBanner(
                onOpenSettings: {
                    permissions.requestAccessibilityPermission()
                    permissions.openAccessibilitySettings()
                },
                onDismiss: { showPermissionBanner = false }
            )
        }
    }

    private var shouldShowPermissionBanner: Bool {
        !permissions.isAccessibilityGranted && showPermissionBanner
    }

    private func refreshOnChange() {
        Task { await viewModel.refresh() }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                isSidebarCollapsed.toggle()
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .buttonStyle(.plain)
            .help(isSidebarCollapsed ? "Show Filters" : "Hide Filters")

            pauseButton
            statusPill

            HStack(spacing: 4) {
                Text("Today ·").foregroundColor(.secondary)
                Text(DurationFormat.short(viewModel.totalTrackedToday)).fontWeight(.semibold)
                Text("tracked").foregroundColor(.secondary)
            }
            .font(.system(size: 12))

            Spacer()

            Button {
                viewModel.collapseAll()
            } label: {
                Image(systemName: "chevron.up.2")
            }
            .buttonStyle(.plain)
            .help("Collapse All")

            Button {
                viewModel.expandAll()
            } label: {
                Image(systemName: "chevron.down.2")
            }
            .buttonStyle(.plain)
            .help("Expand All")

            Button {
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button {
                isTimelineCollapsed.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .buttonStyle(.plain)
            .help(isTimelineCollapsed ? "Show Daily Timeline" : "Hide Daily Timeline")


        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.appToolbarBackground)
    }

    private var pauseButton: some View {
        Button(action: onTogglePause) {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .help(isPaused ? "Resume tracking" : "Pause tracking")
    }

    private var statusPill: some View {
        Button(action: onTogglePause) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isPaused ? Color.secondary : Color.green)
                    .frame(width: 7, height: 7)
                Text(isPaused ? "Paused" : "Recording")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .help(isPaused ? "Click to resume tracking" : "Click to pause tracking")
    }
}
