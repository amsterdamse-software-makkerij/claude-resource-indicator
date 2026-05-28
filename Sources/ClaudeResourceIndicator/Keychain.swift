import Foundation

struct Credentials: Sendable {
    let accessToken: String
    let expiresAt: Date?
    let subscriptionType: String?   // e.g. "max", "pro"

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }
}

enum KeychainError: Error {
    case notFound          // item missing -> user never signed in
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
            throw KeychainError.notFound
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw KeychainError.notFound
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { throw KeychainError.notFound }
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

        var expiry: Date? = nil
        if let ms = oauth["expiresAt"] as? Double {
            expiry = Date(timeIntervalSince1970: ms / 1000.0)
        } else if let ms = oauth["expiresAt"] as? Int {
            expiry = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        }

        let subscription = oauth["subscriptionType"] as? String
        return Credentials(accessToken: token, expiresAt: expiry, subscriptionType: subscription)
    }
}
