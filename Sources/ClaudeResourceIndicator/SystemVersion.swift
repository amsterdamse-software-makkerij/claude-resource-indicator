import Foundation

// Inspects the running macOS version once to decide how the traffic-light colors
// should be shaded. Tahoe (26) received the brighter treatment and reads well; Sequoia
// (15) and older render those same colors too lightly against their lighter translucent
// menu panel, so they get a deeper, higher-contrast shade instead.
//
// The OS version cannot change while the app runs, so the decision is computed once.
enum SystemVersion {
    static let current = ProcessInfo.processInfo.operatingSystemVersion

    static var major: Int { current.majorVersion }

    /// Darken the traffic-light colors on Sequoia (15) and earlier; keep them as-is on
    /// Tahoe (26) and newer.
    static let usesReadableShades: Bool = major < 26

    /// e.g. "15.5.0" — for diagnostics / self-test output.
    static var description: String {
        "\(current.majorVersion).\(current.minorVersion).\(current.patchVersion)"
    }
}
