import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusController: StatusItemController?

    override nonisolated init() { super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        self.model = model
        self.statusController = StatusItemController(model: model)
        model.start()
    }
}
