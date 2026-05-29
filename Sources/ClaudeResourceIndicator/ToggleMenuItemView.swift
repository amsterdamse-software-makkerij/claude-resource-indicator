import AppKit

// A menu row with a trailing switch — a native-looking toggle that keeps the
// menu open when flipped (custom-view items don't dismiss on interaction).
@MainActor
final class ToggleMenuItemView: NSView {
    private let switchControl = MiniSwitch()
    private let onToggle: @MainActor (Bool) -> Void

    init(title: String, width: CGFloat, isOn: Bool, onToggle: @escaping @MainActor (Bool) -> Void) {
        self.onToggle = onToggle
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 28))

        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 0)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        switchControl.isOn = isOn
        switchControl.target = self
        switchControl.action = #selector(switched)
        switchControl.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        addSubview(switchControl)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            switchControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            switchControl.centerYAnchor.constraint(equalTo: centerYAnchor),
            switchControl.widthAnchor.constraint(equalToConstant: 34),
            switchControl.heightAnchor.constraint(equalToConstant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: switchControl.leadingAnchor, constant: -8),
        ])

        applyControlAppearance()
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    func setOn(_ isOn: Bool) { switchControl.isOn = isOn }

    // Resolve colors against a concrete (non-vibrant) appearance matching the
    // system, so the accent fill is the real accent rather than a menu-vibrancy
    // variant. Re-applied on menu open to track Light/Dark changes.
    func applyControlAppearance() {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
        appearance = NSAppearance(named: match)
    }

    @objc private func switched() { onToggle(switchControl.isOn) }
}

// NSSwitch's accent tint is suppressed by the menu's vibrancy (it renders grey
// when on). Drawing the track/knob ourselves with explicit colors — and opting
// out of vibrancy — guarantees the accent shows.
@MainActor
final class MiniSwitch: NSControl {
    var isOn: Bool = false { didSet { needsDisplay = true } }

    override var allowsVibrancy: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: 34, height: 20) }

    override func draw(_ dirtyRect: NSRect) {
        let trackW: CGFloat = 34, trackH: CGFloat = 20
        let track = NSRect(x: (bounds.width - trackW) / 2,
                           y: (bounds.height - trackH) / 2,
                           width: trackW, height: trackH)
        let radius = track.height / 2
        (isOn ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        let inset: CGFloat = 2
        let knobD = track.height - inset * 2
        let knobX = isOn ? track.maxX - inset - knobD : track.minX + inset
        let knobRect = NSRect(x: knobX, y: track.minY + inset, width: knobD, height: knobD)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knobRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        sendAction(action, to: target)
    }
}
