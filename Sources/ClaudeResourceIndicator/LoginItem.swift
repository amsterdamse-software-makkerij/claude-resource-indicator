import AppKit
import ServiceManagement

@MainActor
final class LoginItem: ObservableObject {
    // The toggle is binary, so this stays a Bool — but it now reflects the *true*
    // state: false covers both "not registered" and "registered but awaiting the
    // user's approval in System Settings" (U4). The latter is explained to the
    // user rather than silently collapsed to "off".
    @Published private(set) var isEnabled = false

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
            // U3: surface the failure instead of only NSLog-ing it and snapping
            // the switch back with no explanation.
            NSLog("LoginItem toggle failed: \(error.localizedDescription)")
            presentDeferred(title: enabled ? "Couldn’t enable Launch at Login"
                                           : "Couldn’t disable Launch at Login",
                            message: error.localizedDescription,
                            offerSettings: false)
        }

        // U3: register() can succeed yet leave the item in .requiresApproval —
        // common when the user previously disabled it in System Settings, which
        // then needs manual re-approval. Guide them there rather than flipping the
        // switch off with no reason.
        if enabled, SMAppService.mainApp.status == .requiresApproval {
            presentDeferred(title: "Approve in Login Items",
                            message: "macOS needs you to enable “Claude Resource Indicator” under Login Items in System Settings.",
                            offerSettings: true)
        }

        refreshStatus()
    }

    // Deferred to the next run-loop pass so the alert isn't presented from inside
    // the menu's event-tracking loop (the switch lives in an open menu). Activate
    // first because this is an accessory (LSUIElement) app with no regular window.
    private func presentDeferred(title: String, message: String, offerSettings: Bool) {
        // Task { @MainActor } (not DispatchQueue.main.async) so the AppKit calls
        // below are statically main-actor isolated under strict concurrency, while
        // still deferring past the current menu-tracking turn.
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            if offerSettings {
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Later")
            } else {
                alert.addButton(withTitle: "OK")
            }
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            if offerSettings, response == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }
}
