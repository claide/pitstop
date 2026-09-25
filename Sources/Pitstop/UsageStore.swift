import AppKit
import PitstopCore
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshots: [AccountSnapshot] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var accountsProblem: String?

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// The number shown in the menu bar: your tightest Claude Code limit, falling back to the
    /// tightest limit across all accounts if you don't have a Claude Code account.
    var menuBarRemaining: Double? {
        let claudeWindows = snapshots
            .filter { $0.account.provider == .claude }
            .flatMap(\.windows)
            .filter { $0.kind != .other }
        if let tightestClaude = claudeWindows.map(\.remainingPercent).min() { return tightestClaude }
        return snapshots.flatMap(\.windows).filter { $0.kind != .other }.map(\.remainingPercent).min()
    }

    func refreshIfStale() {
        if let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < 60 { return }
        refresh()
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let loaded = AccountStore.load()
        accountsProblem = loaded.problem
        let active = UsageFetcher.activeAccounts(loaded.accounts)
        Task {
            let results = await UsageFetcher.fetchAll(active)
            snapshots = results
            lastRefresh = .now
            isRefreshing = false
            SnapshotFile.write(results)
            ResetNotifier.schedule(for: results)
        }
    }
}
