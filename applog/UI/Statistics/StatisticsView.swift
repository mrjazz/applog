import SwiftUI

struct StatisticsView: View {
    @ObservedObject var viewModel: StatisticsViewModel
    @ObservedObject var permissions: PermissionsMonitor
    let isPaused: Bool
    let onTogglePause: () -> Void
    @Environment(\.openWindow) private var openWindow
    @State private var showPermissionBanner = true

    var body: some View {
        mainContent
            .frame(minWidth: 920, minHeight: 560)
            .overlay(alignment: .top) { bannerOverlay }
            .task { await viewModel.refresh() }
            .onChange(of: viewModel.minDurationMinutes) { refreshOnChange() }
            .onChange(of: viewModel.searchText) { refreshOnChange() }
            .onChange(of: viewModel.quickSet) { refreshOnChange() }
            .onChange(of: viewModel.filterOnTag) { refreshOnChange() }
            .onChange(of: viewModel.selectedTagID) { refreshOnChange() }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                FilterSidebar(viewModel: viewModel)
                Divider()
                TreeListView(rows: viewModel.rows, maxSeconds: viewModel.maxRowSeconds, selectedNodeID: $viewModel.selectedNodeID)
                    .frame(maxWidth: .infinity)
                Divider()
                TimelinePanel(days: viewModel.timelineDays)
                    .frame(width: 240)
            }
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
            statusPill

            HStack(spacing: 4) {
                Text("Today ·").foregroundColor(.secondary)
                Text(DurationFormat.short(viewModel.totalTrackedToday)).fontWeight(.semibold)
                Text("tracked").foregroundColor(.secondary)
            }
            .font(.system(size: 12))

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Filter by name", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minWidth: 160)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.separator))

            Button {
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
