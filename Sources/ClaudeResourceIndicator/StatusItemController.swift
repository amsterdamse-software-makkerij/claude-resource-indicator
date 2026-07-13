import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let model: AppModel
    private let loginItem = LoginItem()
    private let menu = NSMenu()

    private var hostingView: NSHostingView<MenuContentView>!
    private var launchToggle: ToggleMenuItemView!
    private var cancellable: AnyCancellable?

    // E1: remember what the button is currently showing so a steady poll that
    // returns identical utilization doesn't trigger a fresh off-screen ring draw.
    private var lastRenderedFractions: [Double]?
    private var lastTooltip: String?

    private let contentWidth = MenuContentView.contentWidth

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        buildMenu()
        menu.delegate = self
        statusItem.menu = menu   // system shows + positions the menu on click

        cancellable = model.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.renderStatusIcon(state) }
        renderStatusIcon(model.state)
    }

    // MARK: - Menu

    private func buildMenu() {
        hostingView = NSHostingView(rootView: MenuContentView(model: model))
        hostingView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: 220)
        let contentItem = NSMenuItem()
        contentItem.view = hostingView
        menu.addItem(contentItem)

        menu.addItem(.separator())

        let launchItem = NSMenuItem()
        launchToggle = ToggleMenuItemView(title: "Launch at Login",
                                          width: contentWidth,
                                          isOn: loginItem.isEnabled) { [weak self] isOn in
            guard let self else { return }
            self.loginItem.set(isOn)
            self.launchToggle.setOn(self.loginItem.isEnabled)
        }
        launchItem.view = launchToggle
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Claude Usage", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func sizeContentToFit() {
        hostingView.layoutSubtreeIfNeeded()
        let height = hostingView.fittingSize.height
        hostingView.frame.size = NSSize(width: contentWidth, height: height)
    }

    func menuWillOpen(_ menu: NSMenu) {
        model.isMenuOpen = true
        model.refresh(.open)
        loginItem.refreshStatus()
        launchToggle.setOn(loginItem.isEnabled)
        launchToggle.applyControlAppearance()
        sizeContentToFit()
    }

    func menuDidClose(_ menu: NSMenu) {
        model.isMenuOpen = false
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Status bar icon

    private func renderStatusIcon(_ state: LoadState) {
        guard let button = statusItem.button else { return }
        let specs = ringSpecs(for: state)
        let fractions = specs.map(\.fraction)
        let tip = tooltip(for: state)

        // E1: the image (rings) and tooltip are the only visible output. If both
        // are unchanged, rebuilding the NSImage would be a full off-screen
        // CoreGraphics draw for zero visual change — skip it. The tooltip is part
        // of the signature so state-only transitions (e.g. .loaded -> .offline
        // with the same last-known numbers) still update it.
        if fractions == lastRenderedFractions && tip == lastTooltip { return }
        lastRenderedFractions = fractions
        lastTooltip = tip

        button.image = RingRenderer.image(for: specs)
        button.toolTip = tip
    }

    private func ringSpecs(for state: LoadState) -> [RingSpec] {
        // Menu-bar rings are monochrome (see RingRenderer). Staleness is conveyed
        // by the tooltip and the menu's sync note. States with no data show an
        // empty ring.
        guard let snapshot = state.snapshot else { return [] }
        return snapshot.values.map { RingSpec(fraction: $0.fraction) }
    }

    private func tooltip(for state: LoadState) -> String {
        switch state {
        case .loading:        return "Loading…"
        case .notSignedIn:    return "Not signed in — open Claude Code"
        case .noSubscription: return "No Pro/Max subscription detected"
        case .expired:        return "Token expired — open Claude Code to refresh"
        case .offline:        return "Offline — showing last known usage"
        case .rateLimited:    return "Rate limited — retrying shortly"
        case .error(let m, _): return m
        case .loaded(let snapshot):
            return snapshot.values
                .map { "\($0.metric.shortLabel) \(percentText($0.utilization))" }
                .joined(separator: " · ")
        }
    }
}
