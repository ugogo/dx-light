import Foundation
import ServiceManagement

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var detail: String?

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled

        switch status {
        case .enabled, .notRegistered:
            detail = nil
        case .requiresApproval:
            detail = "Allow DX Light in Login Items."
        case .notFound:
            detail = "Build and launch the app bundle first."
        @unknown default:
            detail = "Login item status is unavailable."
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            refreshStatus()
        } catch {
            refreshStatus()
            detail = error.localizedDescription
        }
    }
}
