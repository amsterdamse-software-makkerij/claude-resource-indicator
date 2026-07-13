import Foundation

// Raw shape of GET https://api.anthropic.com/api/oauth/usage
struct UsageResponse: Decodable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let extraUsage: ExtraUsage?
}

struct UsageWindow: Decodable {
    let utilization: Double?
    let resetsAt: Date?
}

struct ExtraUsage: Decodable {
    let isEnabled: Bool?
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?
    let currency: String?
}

// Which limit window a ring/bar represents. Order is the menu-bar left-to-right order.
enum Metric: Int, CaseIterable, Sendable {
    case session, weekly, opus

    var title: String {
        switch self {
        case .session: return "Current session"
        case .weekly:  return "Weekly (all models)"
        case .opus:    return "Weekly (Opus)"
        }
    }

    var shortLabel: String {
        switch self {
        case .session: return "S"
        case .weekly:  return "W"
        case .opus:    return "O"
        }
    }

    // Session resets within hours (relative); weekly windows show a weekday + time.
    var resetStyle: ResetStyle { self == .session ? .relative : .weekday }

    // The window length shown in the ring center — a display string kept in the
    // model rather than special-cased against shortLabel in the view (Q1).
    var windowLabel: String {
        switch self {
        case .session: return "5h"
        case .weekly:  return "7d"
        case .opus:    return "7d"
        }
    }
}

enum ResetStyle { case relative, weekday }

struct MetricValue: Sendable {
    let metric: Metric
    let utilization: Double   // clamped 0...100 at construction
    let resetsAt: Date?

    // Clamp at the single normalization point (D1): the endpoint is undocumented,
    // so a >100 overage, a negative sentinel, or a 0–1 fraction shouldn't reach the
    // ring/percent math. `fraction` is then 0...1 by construction — the one place
    // the 0–1 conversion lives (Q2), instead of `min(1, util/100)` copy-pasted around.
    init(metric: Metric, utilization: Double, resetsAt: Date?) {
        self.metric = metric
        self.utilization = max(0, min(100, utilization))
        self.resetsAt = resetsAt
    }

    var fraction: Double { utilization / 100 }
}

// A successfully fetched, normalized snapshot.
struct UsageSnapshot: Sendable {
    let values: [MetricValue]          // only metrics the API reported (nulls dropped)
    let extraUsage: ExtraUsageInfo?
    let plan: String?                  // subscription type, e.g. "max"
    let fetchedAt: Date

    func value(for metric: Metric) -> MetricValue? {
        values.first { $0.metric == metric }
    }
}

struct ExtraUsageInfo: Sendable {
    let utilization: Double?
    let usedCredits: Double?
    let monthlyLimit: Double?
    let currency: String?
}

// Everything the UI needs to render, including non-OK states.
enum LoadState: Sendable {
    case loading
    case loaded(UsageSnapshot)
    case notSignedIn
    case noSubscription
    case expired(lastKnown: UsageSnapshot?)
    case offline(lastKnown: UsageSnapshot?)
    case rateLimited(retryAfter: TimeInterval?, lastKnown: UsageSnapshot?)
    case error(message: String, lastKnown: UsageSnapshot?)

    var snapshot: UsageSnapshot? {
        switch self {
        case .loaded(let s): return s
        case .expired(let s), .offline(let s), .rateLimited(_, let s): return s
        case .error(_, let s): return s
        default: return nil
        }
    }
}
