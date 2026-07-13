import AppKit

// B1: diagnostic entry points ship only in DEBUG builds, so the released binary
// exposes no undocumented `--selftest` / `--render-rings` flags. `make selftest`
// builds the debug variant.
#if DEBUG
if CommandLine.arguments.contains("--selftest") {
    SelfTest.run()
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--render-rings"),
   i + 1 < CommandLine.arguments.count {
    RenderTest.writeRings(to: CommandLine.arguments[i + 1])
    exit(0)
}
#endif

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
