import SwiftUI

/// Shown as a tooltip-style overlay pinned to the top of the Statistics
/// window whenever Accessibility access hasn't been granted (FR-35). Tracking
/// still runs at app-level granularity without it; this banner explains what's
/// missing and offers a one-click path to fix it, without ever blocking the
/// window with a modal.
struct PermissionBanner: View {
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text("Accessibility access needed")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("Without it, AppTracker can only see which app is frontmost — not window titles, tabs, or documents. Grant access in System Settings to unlock the full tree.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(spacing: 6) {
                Button("Open System Settings…", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Not Now", action: onDismiss)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.orange.opacity(0.35)))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .padding(.top, 10)
    }
}
