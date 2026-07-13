import Foundation

enum UsageService {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    // Only skip the request locally when the token is clearly past expiry; near
    // the boundary we defer to the server's 401/403 (D5).
    private static let expiryLeeway: TimeInterval = 300

    // S1: a private ephemeral session for this Bearer-token request — no shared
    // cache/cookie/credential storage, and never serve a cached response.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    // Runs the full pipeline once: keychain -> network -> parse -> normalize.
    // Returns a LoadState ready for the UI. `lastKnown` lets transient failures
    // keep showing the previous numbers (dimmed) instead of blanking out.
    static func fetch(lastKnown: UsageSnapshot?) async -> LoadState {
        let creds: Credentials
        do {
            creds = try ClaudeCredentials.read()
        } catch KeychainError.notFound {
            return .notSignedIn
        } catch {
            return .error(message: "Couldn't read credentials", lastKnown: lastKnown)
        }

        if creds.isExpired(skew: expiryLeeway) {
            // Read-only policy: never refresh the shared token ourselves.
            return .expired(lastKnown: lastKnown)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .offline(lastKnown: lastKnown)
        }

        guard let http = response as? HTTPURLResponse else {
            return .error(message: "Unexpected response", lastKnown: lastKnown)
        }

        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            return .expired(lastKnown: lastKnown)
        case 429:
            let retry = retryAfterSeconds(http.value(forHTTPHeaderField: "Retry-After"))
            return .rateLimited(retryAfter: retry, lastKnown: lastKnown)
        case 500...599:
            // Transient server-side; treat like a network blip.
            return .offline(lastKnown: lastKnown)
        default:
            return .error(message: "HTTP \(http.statusCode)", lastKnown: lastKnown)
        }

        // D4: a 200 with a non-JSON body (captive portal / proxy HTML) or an empty
        // body isn't usage data — treat it as a transient blip, not a schema-drift
        // parse error. (An empty JSON object `{}` still decodes to .noSubscription.)
        guard looksLikeJSONBody(contentType: http.value(forHTTPHeaderField: "Content-Type"), data: data) else {
            return .offline(lastKnown: lastKnown)
        }

        guard let parsed = try? decoder.decode(UsageResponse.self, from: data) else {
            return .error(message: "Couldn't parse usage", lastKnown: lastKnown)
        }

        var values: [MetricValue] = []
        if let v = parsed.fiveHour?.utilization {
            values.append(MetricValue(metric: .session, utilization: v, resetsAt: parsed.fiveHour?.resetsAt))
        }
        if let v = parsed.sevenDay?.utilization {
            values.append(MetricValue(metric: .weekly, utilization: v, resetsAt: parsed.sevenDay?.resetsAt))
        }
        if let v = parsed.sevenDayOpus?.utilization {
            values.append(MetricValue(metric: .opus, utilization: v, resetsAt: parsed.sevenDayOpus?.resetsAt))
        }

        guard !values.isEmpty else {
            // 200 with no windows -> token works but no subscription limits apply.
            return .noSubscription
        }

        let extra: ExtraUsageInfo? = {
            guard let e = parsed.extraUsage, e.isEnabled == true else { return nil }
            return ExtraUsageInfo(utilization: e.utilization,
                                  usedCredits: e.usedCredits,
                                  monthlyLimit: e.monthlyLimit,
                                  currency: e.currency)
        }()

        let snapshot = UsageSnapshot(values: values, extraUsage: extra,
                                     plan: creds.subscriptionType, fetchedAt: Date())
        return .loaded(snapshot)
    }

    // Retry-After is usually integer delta-seconds, but RFC 7231 also allows an
    // HTTP-date. Parse both; return nil (→ local exponential backoff) for anything
    // unrecognized (D3). Anthropic currently sends integer seconds, so the date
    // path is defensive.
    static func retryAfterSeconds(_ header: String?, now: Date = Date()) -> TimeInterval? {
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else { return nil }
        if let seconds = Double(header) { return max(0, seconds) }
        if let date = httpDateFormatter.date(from: header) { return max(0, date.timeIntervalSince(now)) }
        return nil
    }

    // True when a 200 body is plausibly the JSON we expect. An empty body is
    // rejected; a present, non-JSON Content-Type (captive portal / proxy HTML) is
    // rejected; an absent Content-Type is treated leniently so servers that omit
    // it but return JSON still decode (D4).
    static func looksLikeJSONBody(contentType: String?, data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        guard let contentType else { return true }
        return contentType.lowercased().contains("json")
    }

    // RFC 7231 IMF-fixdate, e.g. "Sun, 06 Nov 1994 08:49:37 GMT".
    private static let httpDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = ISO8601Parsing.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "Unrecognized date: \(string)")
        }
        return d
    }()
}

// The endpoint returns timestamps like 2026-05-28T11:20:00.428641+00:00
// (microsecond fraction, explicit offset). ISO8601DateFormatter can be picky
// about fractional digit counts, so try a few shapes.
enum ISO8601Parsing {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let withoutFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(from string: String) -> Date? {
        if let d = withFraction.date(from: string) { return d }
        if let d = withoutFraction.date(from: string) { return d }
        // Strip a fractional-seconds component of any length and retry.
        if let dotRange = string.range(of: #"\.\d+"#, options: .regularExpression) {
            let stripped = string.replacingCharacters(in: dotRange, with: "")
            if let d = withoutFraction.date(from: stripped) { return d }
        }
        return nil
    }
}
