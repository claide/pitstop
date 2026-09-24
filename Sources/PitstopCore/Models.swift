import Foundation

public enum ProviderKind: String, Codable, CaseIterable, Sendable {
    case claude, codex

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}

/// `session` is the short window (5h). `weekly` is the long window (7 days,
/// or monthly on some free plans). `other` covers extras like per-model limits.
public enum WindowKind: String, Codable, Sendable {
    case session, weekly, other
}

public struct UsageWindow: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let kind: WindowKind
    public let label: String
    public let usedPercent: Double      // 0...100
    public let resetsAt: Date?

    public init(id: String, kind: WindowKind, label: String, usedPercent: Double, resetsAt: Date?) {
        self.id = id
        self.kind = kind
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double { max(0, 100 - usedPercent) }
}

/// One login for one tool. Stored in ~/Library/Application Support/Pitstop/accounts.json.
public struct Account: Identifiable, Hashable, Codable, Sendable {
    public var id: String                 // stable slug, e.g. "claude-personal"
    public var name: String               // shown in the menu, used by `--account`
    public var provider: ProviderKind
    public var configDir: String?         // CLAUDE_CONFIG_DIR / CODEX_HOME; nil = default folder
    public var keychainService: String?   // Claude only; needed for non-default config dirs
    public var enabled: Bool?             // nil = enabled

    public init(id: String, name: String, provider: ProviderKind,
                configDir: String? = nil, keychainService: String? = nil, enabled: Bool? = nil) {
        self.id = id
        self.name = name
        self.provider = provider
        self.configDir = configDir
        self.keychainService = keychainService
        self.enabled = enabled
    }

    public var isEnabled: Bool { enabled ?? true }

    public var usesDefaultDir: Bool { configDir?.isEmpty ?? true }

    public var resolvedDir: String {
        if let dir = configDir, !dir.isEmpty { return (dir as NSString).expandingTildeInPath }
        return NSHomeDirectory() + (provider == .claude ? "/.claude" : "/.codex")
    }
}

public struct AccountSnapshot: Identifiable, Codable, Sendable {
    public var id: String { account.id }
    public let account: Account
    public var windows: [UsageWindow]
    public var note: String?
    public var error: String?
    public var fetchedAt: Date

    public func window(_ kind: WindowKind) -> UsageWindow? {
        windows.first { $0.kind == kind }
    }
}

public enum ProviderError: LocalizedError {
    case notSignedIn(String)
    case expired(String)
    case badResponse(String)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn(let m), .expired(let m), .badResponse(let m): return m
        }
    }
}

/// Parses ISO-8601 dates, tolerating microsecond fractions like "2026-09-24T15:00:00.123456+00:00".
func parseISODate(_ string: String?) -> Date? {
    guard var s = string else { return nil }
    if let r = s.range(of: #"\.\d+"#, options: .regularExpression) { s.removeSubrange(r) }
    return ISO8601DateFormatter().date(from: s)
}
