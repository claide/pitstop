import Foundation
import PitstopCore

let usage = """
pitstop: check AI quota from the terminal

USAGE
  pitstop status [--json]
      Show every account's limits and reset times.

  pitstop check (--points N [--size light|normal|heavy] | --need session:40,weekly:8)
                [--provider claude|codex] [--account NAME] [--json]
      Decide whether a ticket fits. Exit codes: 0 go/tight, 1 wait, 2 unknown, 3 split.

  pitstop mark start|end TICKET [--points N] [--size light|normal|heavy]
      Record usage before and after a ticket, to calibrate estimates.

  pitstop calibrate [--apply] [--force]
      Compare real ticket costs with the estimate table. --apply saves the new
      table (needs 10 finished tickets unless --force).

  pitstop accounts
      Show configured accounts and where accounts.json lives.
"""

let args = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func has(_ name: String) -> Bool { args.contains(name) }

func warn(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func fail(_ message: String, code: Int32 = 64) -> Never {
    warn(message)
    exit(code)
}

func printJSON<T: Encodable>(_ value: T) {
    if let data = try? PitstopJSON.encoder.encode(value), let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}

func parseSize() -> TicketSize {
    guard let raw = option("--size") else { return .normal }
    guard let size = TicketSize(rawValue: raw.lowercased()) else { fail("--size must be light, normal or heavy.") }
    return size
}

func parsePoints() -> Double? {
    guard let raw = option("--points") else { return nil }
    guard let points = Double(raw), points > 0 else { fail("--points must be a positive number.") }
    return points
}

func loadAndFetch(provider: ProviderKind? = nil) async -> [AccountSnapshot] {
    let loaded = AccountStore.load()
    if let problem = loaded.problem { warn(problem) }
    var accounts = UsageFetcher.activeAccounts(loaded.accounts)
    if let provider { accounts = accounts.filter { $0.provider == provider } }
    let snapshots = await UsageFetcher.fetchAll(accounts)
    if provider == nil { SnapshotFile.write(snapshots) }
    return snapshots
}

guard let command = args.first else {
    print(usage)
    exit(0)
}

switch command {
case "status":
    let snapshots = await loadAndFetch()
    if has("--json") { printJSON(snapshots); exit(0) }
    if snapshots.isEmpty { print("No signed-in Claude Code or Codex accounts found.") }
    for snap in snapshots {
        print("\(snap.account.provider.displayName) (\(snap.account.name))")
        if let error = snap.error { print("  ! \(error)") }
        for w in snap.windows {
            let reset = w.resetsAt.map { "resets in \(countdown(to: $0)) (\(resetClock($0)))" } ?? ""
            let label = w.label.padding(toLength: 18, withPad: " ", startingAt: 0)
            print("  \(label)\(percent(w.remainingPercent).padding(toLength: 5, withPad: " ", startingAt: 0)) left   \(reset)")
        }
        if let note = snap.note { print("  \(note)") }
    }

case "check":
    let provider: ProviderKind
    if let raw = option("--provider") {
        guard let p = ProviderKind(rawValue: raw.lowercased()) else { fail("--provider must be claude or codex.") }
        provider = p
    } else {
        provider = .claude
    }

    let need: Need?
    if let raw = option("--need") {
        guard let parsed = Need.parse(raw) else { fail("--need looks like session:40,weekly:8") }
        need = parsed
    } else if let points = parsePoints() {
        need = Estimator.need(points: points, size: parseSize())
    } else {
        fail("check needs --points N or --need session:X,weekly:Y.\n\n\(usage)")
    }

    let snapshots = await loadAndFetch(provider: provider)
    let result = QuotaCheck.run(provider: provider, need: need, accountName: option("--account"), snapshots: snapshots)
    if has("--json") { printJSON(result) } else { print(result.message) }
    exit(result.status.exitCode)

case "mark":
    guard args.count >= 3, ["start", "end"].contains(args[1]) else {
        fail("Usage: pitstop mark start|end TICKET [--points N] [--size light|normal|heavy]")
    }
    let snapshots = await loadAndFetch()
    let mark = TicketMark(ticket: args[2], phase: args[1], points: parsePoints(),
                          size: option("--size") == nil ? nil : parseSize(), snapshots: snapshots)
    do {
        try TicketLog.append(mark)
        print("Recorded \(mark.phase) for \(mark.ticket).")
    } catch {
        fail("Couldn't write the ticket log: \(error.localizedDescription)", code: 1)
    }

case "calibrate":
    let costs = TicketLog.costs()
    let current = Estimator.table()
    let proposed = TicketLog.calibratedTable(from: costs)
    print("Finished tickets with usable data: \(costs.count)\(Estimator.isCalibrated ? " (table already calibrated once)" : "")")
    for cost in costs {
        let pts = cost.points.map { "\(Int($0)) pts" } ?? "? pts"
        let weekly = cost.weekly.map { ", \(percent($0)) weekly" } ?? ""
        print("  \(cost.ticket)  \(pts), \(cost.size?.rawValue ?? "normal"), \(cost.account): \(percent(cost.session)) session\(weekly)")
    }
    print("\nPoints   Current table     Proposed")
    for row in proposed {
        let old = current.first { $0.points == row.points }
        let oldText = old.map { "\(Int($0.session))% / \(Int($0.weekly))%" } ?? "-"
        print("  \(Int(row.points))".padding(toLength: 9, withPad: " ", startingAt: 0)
              + oldText.padding(toLength: 18, withPad: " ", startingAt: 0)
              + "\(Int(row.session))% / \(Int(row.weekly))%")
    }
    if has("--apply") {
        guard costs.count >= 10 || has("--force") else {
            fail("\nOnly \(costs.count) of 10 tickets so far. Keep going, or pass --force.", code: 1)
        }
        do {
            try Estimator.saveTable(proposed)
            print("\nSaved. `pitstop check --points` now uses the calibrated table.")
        } catch {
            fail("Couldn't save the table: \(error.localizedDescription)", code: 1)
        }
    }

case "accounts":
    let loaded = AccountStore.load()
    if let problem = loaded.problem { warn(problem) }
    print("Edit: \(PitstopPaths.accounts.path)\n")
    for account in loaded.accounts {
        let state = !account.isEnabled ? "disabled" : (UsageFetcher.isInstalled(account) ? "found" : "not found")
        print("  \(account.provider.displayName) (\(account.name))  \(account.resolvedDir)  [\(state)]")
    }

case "help", "--help", "-h":
    print(usage)

default:
    fail("Unknown command \"\(command)\".\n\n\(usage)")
}
