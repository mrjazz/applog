import SwiftUI

struct StatisticsView: View {
    @ObservedObject var viewModel: StatisticsViewModel
    @ObservedObject var permissions: PermissionsMonitor
    @Environment(\.openWindow) private var openWindow
    @State private var showPermissionBanner = true

    var body: some View {
        mainContent
            .frame(minWidth: 920, minHeight: 560)
            .overlay(alignment: .top) { bannerOverlay }
            .task { await viewModel.refresh() }
            .onChange(of: viewModel.minDurationMinutes) { _ in refreshOnChange() }
            .onChange(of: viewModel.searchText) { _ in refreshOnChange() }
            .onChange(of: viewModel.quickSet) { _ in refreshOnChange() }
            .onChange(of: viewModel.filterOnTag) { _ in refreshOnChange() }
            .onChange(of: viewModel.selectedTagID) { _ in refreshOnChange() }
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
            HStack(spacing: 4) {
                Text("Today ·").foregroundColor(.secondary)
                Text(DurationFormat.short(viewModel.totalTrackedToday)).fontWeight(.semibold)
                Text("tracked").foregroundColor(.secondary)
            }
            .font(.system(size: 12))

            Spacer()

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
}
