import Foundation

public enum UsageFetcher {
    /// Enabled accounts whose CLI is set up on this Mac.
    public static func activeAccounts(_ accounts: [Account]) -> [Account] {
        accounts.filter { $0.isEnabled && isInstalled($0) }
    }

    public static func isInstalled(_ account: Account) -> Bool {
        switch account.provider {
        case .claude: return ClaudeUsage.isInstalled(account)
        case .codex: return CodexUsage.isInstalled(account)
        }
    }

    public static func fetch(_ account: Account) async -> AccountSnapshot {
        do {
            switch account.provider {
            case .claude:
                let windows = try await ClaudeUsage.fetch(account)
                return AccountSnapshot(account: account, windows: windows, fetchedAt: .now)
            case .codex:
                let result = try await CodexUsage.fetch(account)
                return AccountSnapshot(account: account, windows: result.windows, note: result.note, fetchedAt: .now)
            }
        } catch {
            return AccountSnapshot(account: account, windows: [], error: error.localizedDescription, fetchedAt: .now)
        }
    }

    /// Fetches every account in parallel, keeping the input order.
    public static func fetchAll(_ accounts: [Account]) async -> [AccountSnapshot] {
        await withTaskGroup(of: (Int, AccountSnapshot).self) { group in
            for (index, account) in accounts.enumerated() {
                group.addTask { (index, await UsageFetcher.fetch(account)) }
            }
            var results: [(Int, AccountSnapshot)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}
