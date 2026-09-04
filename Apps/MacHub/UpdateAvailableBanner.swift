import SwiftUI

struct UpdateAvailableBanner: View {
    @ObservedObject var updateController: MacUpdateController

    var body: some View {
        if let version = updateController.availableVersion,
           updateController.shouldShowDashboardBanner {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(MacTheme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("有新版本可用")
                        .font(.headline)
                    Text(verbatim: "TokenWatch v\(version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("更新") {
                    updateController.checkForUpdates()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!updateController.canCheckForUpdates)

                Button {
                    updateController.dismissAvailableUpdate()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("稍后")
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(MacTheme.border, lineWidth: 1)
            }
            .shadow(radius: 8, y: 3)
        }
    }
}
