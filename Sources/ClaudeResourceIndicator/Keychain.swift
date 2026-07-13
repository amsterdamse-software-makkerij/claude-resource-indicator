import Foundation

struct Credentials: Sendable {
    let accessToken: String
    let expiresAt: Date?
    let subscriptionType: String?   // e.g. "max", "pro"

    // Local expiry is only an optimization hint — a way to skip a request we're
    // confident the server would reject. It is NOT authoritative: a device clock
    // a few minutes fast (or a token sitting right at its boundary) shouldn't
    // short-circuit a token the server would still accept. So only treat the
    // token as locally expired once it's past expiry by a comfortable skew
    // margin; otherwise attempt the request and let the 401/403 decide (D5).
    func isExpired(skew: TimeInterval = 0) -> Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt.addingTimeInterval(skew)
    }
}

enum KeychainError: Error {
    case notFound          // item missing -> user never signed in (security exit 44)
    case readFailed        // security couldn't run, or failed for another reason
    case malformed         // item present but unparseable
}

enum ClaudeCredentials {
    static let service = "Claude Code-credentials"

    // We invoke `/usr/bin/security` rather than SecItemCopyMatching on purpose:
    // the keychain item is owned by the Claude Code CLI, and reading it from our
    // own (ad-hoc-signed, hash-changes-every-build) binary would trigger a GUI
    // "allow access" prompt on every rebuild. The `security` tool is already on
    // the item's ACL, so this stays prompt-free and works headlessly.
    static func read() throws -> Credentials {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            // Couldn't even launch `security` — a read failure, not "no item".
            throw KeychainError.readFailed
        }
        process.waitUntilExit()

        // 44 == errSecItemNotFound: the item genuinely isn't there (never signed
        // in). Any other non-zero exit — a locked keychain, an ACL/prompt timeout,
        // a transient error — is a read failure, NOT a sign-out. Mapping those to
        // .notFound would wrongly tell a signed-in user to sign in (R1).
        let status = process.terminationStatus
        guard status == 0 else {
            throw status == 44 ? KeychainError.notFound : KeychainError.readFailed
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { throw KeychainError.readFailed }
        return try parse(data)
    }

    private static func parse(_ data: Data) throws -> Credentials {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String,
            !token.isEmpty
        else {
            throw KeychainError.malformed
        }

        let expiry = parseExpiry(oauth["expiresAt"])
        let subscription = oauth["subscriptionType"] as? String
        return Credentials(accessToken: token, expiresAt: expiry, subscriptionType: subscription)
    }

    // `expiresAt` has only been observed as a millisecond epoch, but the store is
    // undocumented and could drift to a seconds epoch or an ISO-8601 string. Parse
    // all three so local expiry detection doesn't silently switch off — a nil
    // expiry reads as "never expires" (D2).
    static func parseExpiry(_ raw: Any?) -> Date? {
        switch raw {
        case let number as NSNumber:
            return epochDate(number.doubleValue)
        case let string as String:
            if let date = ISO8601Parsing.date(from: string) { return date }
            if let number = Double(string) { return epochDate(number) }
            return nil
        default:
            return nil
        }
    }

    // Disambiguate seconds vs milliseconds by magnitude: a modern ms epoch is
    // ~1e12+, a seconds epoch ~1e9. The gap is wide enough that a single threshold
    // is unambiguous for any plausible date.
    private static func epochDate(_ value: Double) -> Date? {
        guard value > 0 else { return nil }
        let seconds = value > 1e11 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }
}
