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

    private let pollInterval: TimeInterval = 60
    private let onOpenDebounce: TimeInterval = 15
    private let minRequestSpacing: TimeInterval = 1   // hard floor: never >1 req/sec
    private let maxBackoff: TimeInterval = 600

    private var timer: Timer?
    private var isAsleep = false
    private var isOnline = true
    private let pathMonitor = NWPathMonitor()

    private var inFlight = false
    private var lastFetchAt: Date = .distantPast
    private var backoffUntil: Date = .distantPast
    private var currentBackoff: TimeInterval = 0

    func start() {
        observeSystem()
        startMonitoringNetwork()
        schedulePolling()
        refresh(.auto)
    }

    func refresh(_ reason: RefreshReason) {
        let now = Date()

        // Hard backoff after a rate-limit applies to every trigger — forcing a
        // request while throttled would just earn another 429.
        if now < backoffUntil { return }

        // Global floor: coalesce any triggers that land within 1s of each other
        // (e.g. wake + network-restored firing together) so we never burst.
        if now.timeIntervalSince(lastFetchAt) < minRequestSpacing { return }

        switch reason {
        case .auto:   break
        case .open:   if now.timeIntervalSince(lastFetchAt) < onOpenDebounce { return }
        }

        guard !inFlight else { return }
        inFlight = true
        lastFetchAt = now

        let lastKnown = state.snapshot
        Task {
            let newState = await UsageService.fetch(lastKnown: lastKnown)
            self.apply(newState)
            self.inFlight = false
        }
    }

    private func apply(_ newState: LoadState) {
        state = newState
        switch newState {
        case .rateLimited(let retryAfter, _):
            let wait = retryAfter ?? nextBackoff()
            backoffUntil = Date().addingTimeInterval(wait)
            scheduleBackoffRetry(after: wait)
        case .loaded:
            currentBackoff = 0
        default:
            break
        }
    }

    private func nextBackoff() -> TimeInterval {
        currentBackoff = currentBackoff == 0 ? 60 : min(currentBackoff * 2, maxBackoff)
        return currentBackoff
    }

    private func scheduleBackoffRetry(after wait: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + wait + 0.5) { [weak self] in
            self?.refresh(.auto)
        }
    }

    // MARK: - Polling

    private func schedulePolling() {
        timer?.invalidate()
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollIfActive() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func pollIfActive() {
        guard !isAsleep, isOnline else { return }
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
