import Foundation

// Headless end-to-end check of the data pipeline (keychain -> network -> parse).
// Run via `make selftest`. Prints the resolved state and exits.
// B1: compiled into DEBUG builds only — not shipped in release.
#if DEBUG
enum SelfTest {
    static func run() {
        print("== Claude Resource Indicator self-test ==")
        verifyColorMode()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            let state = await UsageService.fetch(lastKnown: nil)
            report(state)
            semaphore.signal()
        }
        semaphore.wait()
    }

    // Reports the detected OS version and which percentage-text color it selects. Uses an
    // explicit PASS/FAIL print rather than `assert` so the check still runs in the release
    // self-test build.
    private static func verifyColorMode() {
        let mode = SystemVersion.usesReadableShades
            ? "default label color (below Tahoe)"
            : "traffic-light color (Tahoe+)"
        print("macOS: \(SystemVersion.description)  (major \(SystemVersion.major))")
        print("Bar percentage text: \(mode)")

        let passed = SystemVersion.usesReadableShades == (SystemVersion.major < 26)
        print("  [\(passed ? "PASS" : "FAIL")] mode gate matches major < 26")
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE yyyy-MM-dd HH:mm"
        return f
    }()

    private static func report(_ state: LoadState) {
        switch state {
        case .loading:
            print("State: LOADING")
        case .notSignedIn:
            print("State: NOT SIGNED IN (no keychain credentials)")
        case .noSubscription:
            print("State: NO SUBSCRIPTION (200 but no usage windows)")
        case .expired:
            print("State: EXPIRED (token past expiry or 401/403)")
        case .offline:
            print("State: OFFLINE (network request failed)")
        case .rateLimited(let retryAfter, _):
            print("State: RATE LIMITED (429)  retryAfter=\(retryAfter.map { "\($0)s" } ?? "—")")
        case .error(let message, _):
            print("State: ERROR — \(message)")
        case .loaded(let snapshot):
            print("State: LOADED  (\(snapshot.values.count) metric(s))")
            for value in snapshot.values {
                let reset = value.resetsAt.map { stamp.string(from: $0) } ?? "—"
                print(String(format: "  %-22@ %5.1f%%   resets %@",
                             value.metric.title as NSString, value.utilization, reset))
            }
            if let extra = snapshot.extraUsage {
                print("  extra usage enabled: util=\(extra.utilization.map { String($0) } ?? "—")")
            }
        }
    }
}
#endif
