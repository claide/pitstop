import Foundation

/// Reads Claude Code's existing OAuth login and asks Anthropic for current limits.
///
/// - The token is read with /usr/bin/security, so the Keychain prompt names "security"
///   and "Always Allow" survives rebuilds of Pitstop.
/// - /api/oauth/usage is undocumented and may change. Reading it does not use quota.
/// - Pitstop never refreshes the token itself: that rotates the refresh token and could
///   sign Claude Code out. If it's expired, running `claude` fixes it.
enum ClaudeUsage {
    static let defaultService = "Claude Code-credentials"

    static func isInstalled(_ account: Account) -> Bool {
        FileManager.default.fileExists(atPath: account.resolvedDir)
    }

    static func fetch(_ account: Account) async throws -> [UsageWindow] {
        let token = try accessToken(for: account)

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            throw ProviderError.expired("Claude login expired. Run `claude` once to refresh it.")
        }
        guard status == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.badResponse("Claude usage check failed (HTTP \(status)).")
        }

        var windows: [UsageWindow] = []
        if let w = window(json, key: "five_hour", kind: .session, label: "Session (5h)") { windows.append(w) }
        if let w = window(json, key: "seven_day", kind: .weekly, label: "Weekly") { windows.append(w) }
        for key in json.keys.sorted() where key.hasPrefix("seven_day_") {
            let model = key.dropFirst("seven_day_".count).capitalized
            if let w = window(json, key: key, kind: .other, label: "Weekly, \(model)") { windows.append(w) }
        }
        return windows
    }

    private static func window(_ json: [String: Any], key: String, kind: WindowKind, label: String) -> UsageWindow? {
        guard let w = json[key] as? [String: Any],
              let used = (w["utilization"] as? NSNumber)?.doubleValue else { return nil }
        return UsageWindow(id: key, kind: kind, label: label, usedPercent: used,
                           resetsAt: parseISODate(w["resets_at"] as? String))
    }

    private static func accessToken(for account: Account) throws -> String {
        var raw: Data?
        if let service = account.keychainService {
            raw = keychainItem(service: service)
        } else if account.usesDefaultDir {
            raw = keychainItem(service: defaultService)
        }
        // Fallback for logins stored on disk instead of the Keychain.
        if raw == nil {
            raw = FileManager.default.contents(atPath: account.resolvedDir + "/.credentials.json")
        }

        guard let raw,
              let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            if !account.usesDefaultDir && account.keychainService == nil {
                throw ProviderError.notSignedIn("Set keychainService for \"\(account.name)\" in accounts.json.")
            }
            throw ProviderError.notSignedIn("No Claude Code login found. Run `claude` and sign in with your subscription.")
        }
        if let expiresMs = (oauth["expiresAt"] as? NSNumber)?.doubleValue,
           Date(timeIntervalSince1970: expiresMs / 1000) < .now {
            throw ProviderError.expired("Claude login expired. Run `claude` once to refresh it.")
        }
        return token
    }

    private static func keychainItem(service: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }
}
