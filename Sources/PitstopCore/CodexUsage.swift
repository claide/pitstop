import Foundation

/// Reads the rate-limit snapshot Codex CLI writes into its session logs
/// (<CODEX_HOME>/sessions/YYYY/MM/DD/rollout-*.jsonl). No network, no keys.
///
/// The numbers are as of your last Codex request. If a window's reset time has
/// passed since then, it's shown as fully available.
enum CodexUsage {
    static func isInstalled(_ account: Account) -> Bool {
        FileManager.default.fileExists(atPath: account.resolvedDir + "/sessions")
    }

    static func fetch(_ account: Account) async throws -> (windows: [UsageWindow], note: String) {
        let root = URL(fileURLWithPath: account.resolvedDir).appendingPathComponent("sessions")
        for file in recentRolloutFiles(root: root) {
            if let windows = latestRateLimits(in: file) {
                let when = modDate(file).formatted(.relative(presentation: .named))
                return (windows, "As of your last Codex run, \(when)")
            }
        }
        throw ProviderError.notSignedIn("No Codex usage yet. Run one Codex request to see limits.")
    }

    private static func latestRateLimits(in file: URL) -> [UsageWindow]? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  let limits = payload["rate_limits"] as? [String: Any] else { continue }

            let eventTime = parseISODate(obj["timestamp"] as? String) ?? modDate(file)
            var windows: [UsageWindow] = []
            for key in ["primary", "secondary"] {
                guard let w = limits[key] as? [String: Any],
                      let used = (w["used_percent"] as? NSNumber)?.doubleValue else { continue }
                let minutes = (w["window_minutes"] as? NSNumber)?.doubleValue

                var resets: Date?
                if let at = (w["resets_at"] as? NSNumber)?.doubleValue {
                    resets = Date(timeIntervalSince1970: at)
                } else if let inSeconds = (w["resets_in_seconds"] as? NSNumber)?.doubleValue {
                    resets = eventTime.addingTimeInterval(inSeconds)
                }
                let alreadyReset = resets.map { $0 < .now } ?? false

                let kind: WindowKind
                if let minutes { kind = minutes <= 1_440 ? .session : .weekly }
                else { kind = key == "primary" ? .session : .weekly }

                windows.append(UsageWindow(
                    id: key,
                    kind: kind,
                    label: label(minutes: minutes, kind: kind),
                    usedPercent: alreadyReset ? 0 : used,
                    resetsAt: alreadyReset ? nil : resets))
            }
            if !windows.isEmpty { return windows }
        }
        return nil
    }

    private static func label(minutes: Double?, kind: WindowKind) -> String {
        guard let m = minutes else { return kind == .session ? "Session" : "Weekly" }
        if m == 300 { return "Session (5h)" }
        if m == 10_080 { return "Weekly" }
        if m >= 40_000 { return "Monthly" }
        if m >= 1_440 { return "\(Int(m / 1_440))-day window" }
        return "\(Int(m / 60))h window"
    }

    /// Newest session files first, walking year/month/day folders from the latest.
    private static func recentRolloutFiles(root: URL, limit: Int = 20) -> [URL] {
        let fm = FileManager.default
        func subfolders(_ url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        var files: [URL] = []
        outer: for year in subfolders(root) {
            for month in subfolders(year) {
                for day in subfolders(month) {
                    let rollouts = ((try? fm.contentsOfDirectory(at: day, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                        .filter { $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl" }
                    files.append(contentsOf: rollouts)
                    if files.count >= limit { break outer }
                }
            }
        }
        return files.sorted { modDate($0) > modDate($1) }
    }

    private static func modDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
