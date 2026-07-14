# OS-aware readable percentage text

**Date:** 2026-07-14
**Status:** Approved for implementation

## Problem

The traffic-light colors (`systemGreen` / `systemOrange` / `systemRed`) look good on
macOS Tahoe (26), but on Sequoia (15) and older they render too lightly against the
lighter translucent menu panel. The worst offender is the percentage number at the
top-right of each horizontal bar — the light green/orange text is hard to read.

## Goal

On Sequoia and older, keep everything the same except the bar percentage number, which
is painted in the default system label color (black in light theme, white in dark theme)
so it is always legible. No new colors are defined. Tahoe (26+) renders exactly as today.

## Design

### 1. Version verification subroutine

A small, self-contained helper that inspects the running OS once:

```swift
enum SystemVersion {
    static let current = ProcessInfo.processInfo.operatingSystemVersion
    static var major: Int { current.majorVersion }
    // Tahoe (26) reads well as-is; Sequoia (15) and older need the readability fallback.
    static let usesReadableShades: Bool = major < 26
}
```

- The OS version does not change while the app runs, so the flag is a cached `static let`.
- The cutoff is `major < 26`: Sequoia (15) and earlier get the fallback; Tahoe (26+) keeps
  the current colors. Safer than `major == 15` because older systems share Sequoia's
  lighter appearance.

### 2. The change — bar percentage text only

`BarRow` in `MenuContentView.swift` already renders the percentage with the traffic-light
color. Below Tahoe, that single text uses the default label color instead:

```swift
private var percentColor: Color {
    SystemVersion.usesReadableShades ? .primary : color
}
```

`.primary` resolves to `NSColor.labelColor` (black on light, white on dark), so no new
color is defined and it adapts to the theme automatically.

### 3. Untouched

The ring, the bar fills themselves, the center label, track, secondary text, and the
Launch-at-Login toggle all keep their current colors on every OS version. Only the bar
percentage number changes, and only below Tahoe.

### 4. Reporting via `--selftest`

The existing `--selftest` entry point prints the detected OS version and which
percentage-text mode is active, plus a PASS/FAIL check that the gate matches `major < 26`.
This is the user-facing way to confirm the detection on any machine.

## Testing

`SelfTest.swift` prints the OS version + active mode and asserts (via explicit PASS/FAIL
print, so it runs in the release build) that `usesReadableShades == (major < 26)`. The
end-to-end Sequoia appearance cannot be verified on this (Tahoe) machine, but the version
gate is checked and the color fallback is a one-line, theme-adaptive system color.

## Out of scope

- No new/darkened colors, no changes to the ring or bar fills.
- No changes to thresholds (60 / 85), layout, fonts, track color, or the toggle.
- No runtime toggle/preference — behavior is driven purely by OS version.
