import AppKit
import Combine
import Network

enum RefreshReason {
    case auto      // background timer / wake / network-restored
    case open      // menu opened
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: LoadState = .loading

    // Driven by the menu delegate. The menu view uses it to run its countdown
    // ticker only while the dropdown is open (E2).
    @Published var isMenuOpen = false

    private let pollInterval: TimeInterval = 60
    private let dormantPollInterval: TimeInterval = 300   // when expired / not signed in
    private let onOpenDebounce: TimeInterval = 15
    private let minRequestSpacing: TimeInterval = 1   // hard floor: never >1 req/sec
    private let maxBackoff: TimeInterval = 600

    private var timer: Timer?
    private var isAsleep = false
    private var isOnline = true
    private let pathMonitor = NWPathMonitor()

    private var inFlight = false
    private var pendingRefresh = false
    private var lastFetchAt: Date = .distantPast
    private var backoffUntil: Date = .distantPast
    private var currentBackoff: TimeInterval = 0
    private var backoffRetryTask: Task<Void, Never>?

    // States that won't recover through polling — re-auth happens in Claude Code,
    // not here — so the background poll backs off (R5).
    private var isDormant: Bool {
        switch state {
        case .expired, .notSignedIn: return true
        default:                     return false
        }
    }

    func start() {
        observeSystem()
        startMonitoringNetwork()
        schedulePolling()
        refresh(.auto)
    }

    func refresh(_ reason: RefreshReason) {
        let now = Date()

        // Hard backoff after a rate-limit applies to every trigger — forcing a
        // request while throttled would just earn another 429. The backoff retry
        // task (R3) owns the eventual re-check.
        if now < backoffUntil { return }

        // Global floor: coalesce any triggers that land within 1s of each other
        // (e.g. wake + network-restored firing together) so we never burst. If a
        // fetch is already running when we coalesce, don't lose the trigger —
        // remember it and honor it once that fetch completes (R6).
        if now.timeIntervalSince(lastFetchAt) < minRequestSpacing {
            if inFlight { pendingRefresh = true }
            return
        }

        switch reason {
        case .auto:   break
        case .open:   if now.timeIntervalSince(lastFetchAt) < onOpenDebounce { return }
        }

        // R6: a trigger arriving mid-fetch is remembered, not dropped, so a wake
        // or network-restored event during an in-flight request still produces a
        // refresh instead of leaving stale data until the next 60s tick.
        guard !inFlight else { pendingRefresh = true; return }

        inFlight = true
        pendingRefresh = false
        lastFetchAt = now

        let lastKnown = state.snapshot
        Task {
            // R4: always release the in-flight lock, even if fetch ever starts
            // throwing/cancelling, so polling can't wedge permanently. R6: then
            // honor any trigger that landed while this fetch was in flight (the
            // lock is already clear, so the re-run can proceed).
            defer {
                self.inFlight = false
                if self.pendingRefresh {
                    self.pendingRefresh = false
                    self.refresh(.auto)
                }
            }
            let newState = await UsageService.fetch(lastKnown: lastKnown)
            self.apply(newState)
        }
    }

    private func apply(_ newState: LoadState) {
        state = newState
        switch newState {
        case .rateLimited(let retryAfter, _):
            let wait = retryAfter ?? nextBackoff()
            backoffUntil = Date().addingTimeInterval(wait)
            scheduleBackoffRetry(after: wait)
        default:
            // R2: reset backoff on any non-rate-limited outcome, not only .loaded.
            // Otherwise a 429 that bounces through .offline/.error/.expired before
            // the next 429 keeps doubling from a stale counter.
            currentBackoff = 0
            // R3: a good round-trip means the pending 429 retry is moot.
            backoffRetryTask?.cancel()
            backoffRetryTask = nil
        }
    }

    private func nextBackoff() -> TimeInterval {
        currentBackoff = currentBackoff == 0 ? 60 : min(currentBackoff * 2, maxBackoff)
        return currentBackoff
    }

    private func scheduleBackoffRetry(after wait: TimeInterval) {
        // R3: hold the retry as a single cancellable task and replace any existing
        // one, so repeated 429s can't stack independent, uncancellable wakeups.
        backoffRetryTask?.cancel()
        backoffRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((wait + 0.5) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.refresh(.auto)
        }
    }

    // MARK: - Polling

    private func schedulePolling() {
        timer?.invalidate()
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollIfActive() }
        }
        // E3: let the kernel coalesce this all-day wakeup with other timers.
        t.tolerance = pollInterval * 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func pollIfActive() {
        guard !isAsleep, isOnline else { return }
        // R5: an expired token or missing credentials won't fix themselves via
        // polling — re-auth happens in Claude Code. Stretch the background poll
        // way out in those states instead of hammering the endpoint every 60s.
        // Menu-open, wake, and network-restored events bypass this and still
        // refresh immediately, so recovery stays snappy.
        if isDormant, Date().timeIntervalSince(lastFetchAt) < dormantPollInterval { return }
        refresh(.auto)
    }

    // MARK: - Sleep / wake

    private func observeSystem() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isAsleep = true }
        }
        nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isAsleep = false
                self.refresh(.auto)
            }
        }
    }

    // MARK: - Network reachability

    private func startMonitoringNetwork() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let online = path.status == .satisfied
                let cameOnline = online && !self.isOnline
                self.isOnline = online
                if cameOnline { self.refresh(.auto) }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "net.monitor"))
    }
}
