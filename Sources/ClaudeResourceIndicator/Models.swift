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
}

enum ResetStyle { case relative, weekday }

struct MetricValue: Sendable {
    let metric: Metric
    let utilization: Double   // 0...100
    let resetsAt: Date?
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
