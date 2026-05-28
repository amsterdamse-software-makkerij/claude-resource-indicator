import SwiftUI

// The custom view embedded at the top of the status-item menu. Actions
// (Refresh / Launch at login / Quit) are native NSMenuItems, not part of this.
struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @State private var now = Date()

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private let width: CGFloat = 264

    // Only surface the sync note once the displayed numbers are genuinely old —
    // a single failed poll/open right after a good fetch shouldn't alarm.
    private let stalenessThreshold: TimeInterval = 150

    var body: some View {
        Group {
            switch render {
            case .loading:
                loadingView
            case .usage(let snapshot, let note):
                UsageContentView(snapshot: snapshot, note: note, now: now)
            case .message(let info):
                MessageView(info: info)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(width: width)
        .overlay(alignment: .topTrailing) {
            if let plan = planLabel {
                PlanPill(text: plan)
                    .padding(.top, 8)
                    .padding(.trailing, 10)
            }
        }
        .onAppear { now = Date() }
        .onReceive(tick) { now = $0 }
    }

    private var planLabel: String? {
        guard let plan = model.state.snapshot?.plan, !plan.isEmpty else { return nil }
        return plan.capitalized
    }

    private var loadingView: some View {
        HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
            .frame(height: 90)
    }

    private enum Render {
        case loading
        case usage(UsageSnapshot, note: SyncNote?)
        case message(MessageInfo)
    }

    // Once we have any numbers, keep them visible and just annotate transient
    // sync trouble with a calm note — never grey the data out.
    private var render: Render {
        switch model.state {
        case .loading:
            return .loading
        case .loaded(let s):
            return .usage(s, note: nil)
        case .offline(let last):
            if let s = last { return .usage(s, note: staleNote(s)) }
            return .message(MessageInfo(symbol: "wifi.slash",
                                        title: "Waiting for sync…",
                                        subtitle: "Offline — will retry automatically."))
        case .rateLimited(_, let last):
            if let s = last { return .usage(s, note: staleNote(s)) }
            return .message(MessageInfo(symbol: "hourglass",
                                        title: "Waiting for sync…",
                                        subtitle: "Rate limited — retrying automatically."))
        case .error(_, let last):
            if let s = last { return .usage(s, note: staleNote(s)) }
            return .message(MessageInfo(symbol: "arrow.triangle.2.circlepath",
                                        title: "Waiting for sync…",
                                        subtitle: "Couldn't reach usage — retrying."))
        case .expired(let last):
            let note = SyncNote(symbol: "key.slash", text: "Session expired — open Claude Code")
            if let s = last { return .usage(s, note: note) }
            return .message(MessageInfo(symbol: "key.slash",
                                        title: "Session expired",
                                        subtitle: "Open Claude Code to refresh your login."))
        case .notSignedIn:
            return .message(MessageInfo(symbol: "person.crop.circle.badge.exclamationmark",
                                        title: "Not signed in",
                                        subtitle: "Sign in with Claude Code to see usage."))
        case .noSubscription:
            return .message(MessageInfo(symbol: "creditcard",
                                        title: "No subscription",
                                        subtitle: "No Pro/Max usage limits were found."))
        }
    }

    private func staleNote(_ snapshot: UsageSnapshot) -> SyncNote? {
        now.timeIntervalSince(snapshot.fetchedAt) > stalenessThreshold ? .syncing : nil
    }
}

struct UsageContentView: View {
    let snapshot: UsageSnapshot
    let note: SyncNote?
    let now: Date

    var body: some View {
        VStack(spacing: 12) {
            WatchRingsView(values: snapshot.values, now: now)

            VStack(spacing: 10) {
                ForEach(snapshot.values, id: \.metric) { value in
                    BarRow(value: value, now: now)
                }
            }

            if let extra = snapshot.extraUsage {
                ExtraUsageRow(extra: extra)
            }

            if let note {
                SyncNoteRow(note: note)
            }
        }
    }
}

struct PlanPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.trackColor.opacity(0.22)))
    }
}

extension Metric: Identifiable { var id: Int { rawValue } }

struct WatchRingsView: View {
    let values: [MetricValue]
    let now: Date

    private let outerSize: CGFloat = 78
    private let lineWidth: CGFloat = 9
    private let step: CGFloat = 21

    var body: some View {
        ZStack {
            ForEach(Array(values.enumerated()), id: \.element.metric) { index, value in
                ring(for: value, size: outerSize - CGFloat(index) * step)
            }
            centerLabel
        }
        .frame(width: outerSize, height: outerSize)
    }

    private func ring(for value: MetricValue, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Theme.trackColor.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, value.utilization / 100))
                .stroke(Theme.color(forUtilization: value.utilization),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var centerLabel: some View {
        if let primary = values.first {
            VStack(spacing: 0) {
                Text(percentText(primary.utilization))
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                Text(primary.metric.shortLabel == "S" ? "5h" : primary.metric.shortLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct BarRow: View {
    let value: MetricValue
    let now: Date

    private var color: Color { Theme.color(forUtilization: value.utilization) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(value.metric.title).font(.subheadline)
                Spacer()
                Text(percentText(value.utilization))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.trackColor.opacity(0.25))
                    Capsule().fill(color)
                        .frame(width: geo.size.width * CGFloat(min(1, value.utilization / 100)))
                }
            }
            .frame(height: 6)
            Text(ResetFormatter.string(for: value.metric, resetsAt: value.resetsAt, now: now))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct ExtraUsageRow: View {
    let extra: ExtraUsageInfo

    var body: some View {
        HStack {
            Text("Extra usage").font(.caption)
            Spacer()
            Text(detail).font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        if let u = extra.utilization { return percentText(u) }
        if let used = extra.usedCredits { return String(format: "%.2f used", used) }
        return "enabled"
    }
}

struct SyncNote {
    let symbol: String
    let text: String
    static let syncing = SyncNote(symbol: "arrow.triangle.2.circlepath", text: "Waiting for sync…")
}

struct SyncNoteRow: View {
    let note: SyncNote
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: note.symbol)
            Text(note.text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct MessageInfo {
    let symbol: String
    let title: String
    let subtitle: String
}

struct MessageView: View {
    let info: MessageInfo
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: info.symbol)
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(info.title).font(.headline)
            Text(info.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 110)
    }
}
