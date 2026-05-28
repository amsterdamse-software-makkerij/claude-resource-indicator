import Foundation
import ServiceManagement

@MainActor
final class LoginItem: ObservableObject {
    @Published var isEnabled: Bool = false

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("LoginItem toggle failed: \(error.localizedDescription)")
        }
        refreshStatus()
    }
}
