import Foundation

public enum CheckStatus: String, Codable, Sendable {
    case go        // enough left
    case tight     // fits, but with less than `tightMargin` to spare
    case wait      // doesn't fit until a reset
    case split     // ticket too big for one session
    case unknown   // couldn't read usage

    public var exitCode: Int32 {
        switch self {
        case .go, .tight: return 0
        case .wait: return 1
        case .unknown: return 2
        case .split: return 3
        }
    }
}

public struct AccountVerdict: Codable, Sendable {
    public let account: String
    public let status: CheckStatus
    public let sessionLeft: Double?
    public let weeklyLeft: Double?
    public let readyAt: Date?
    public let problem: String?
}

public struct CheckResult: Codable, Sendable {
    public let provider: ProviderKind
    public let need: Need?
    public let status: CheckStatus
    public let chosen: AccountVerdict?
    public let alternatives: [AccountVerdict]
    public let message: String
}

public enum QuotaCheck {
    public static let tightMargin = 10.0

    public static func verdict(for snapshot: AccountSnapshot, need: Need) -> AccountVerdict {
        let session = snapshot.window(.session)
        let weekly = snapshot.window(.weekly)
        func make(_ status: CheckStatus, readyAt: Date? = nil, problem: String? = nil) -> AccountVerdict {
            AccountVerdict(account: snapshot.account.name, status: status,
                           sessionLeft: session?.remainingPercent, weeklyLeft: weekly?.remainingPercent,
                           readyAt: readyAt, problem: problem)
        }
        if let error = snapshot.error { return make(.unknown, problem: error) }

        var status = CheckStatus.go
        var readyAt: Date?
        for (needed, window, name) in [(need.session, session, "session"), (need.weekly, weekly, "weekly")] {
            guard let needed else { continue }
            guard let window else { return make(.unknown, problem: "No \(name) limit reported.") }
            let left = window.remainingPercent
            if left < needed {
                status = .wait
                if let reset = window.resetsAt {
                    readyAt = max(readyAt ?? reset, reset)
                }
            } else if left - needed < tightMargin, status == .go {
                status = .tight
            }
        }
        return make(status, readyAt: status == .wait ? readyAt : nil)
    }

    /// Checks `accountName` (or the first account) and lists other accounts that could take the ticket.
    public static func run(provider: ProviderKind, need: Need?, accountName: String?,
                           snapshots: [AccountSnapshot]) -> CheckResult {
        let candidates = snapshots.filter { $0.account.provider == provider }

        guard let need else {
            return CheckResult(provider: provider, need: nil, status: .split, chosen: nil, alternatives: [],
                               message: "Over \(Int(Estimator.splitAbove)) points: split this ticket before starting.")
        }

        let target: AccountSnapshot?
        if let accountName {
            target = candidates.first { $0.account.name.caseInsensitiveCompare(accountName) == .orderedSame }
        } else {
            target = candidates.first
        }
        guard let target else {
            let which = accountName.map { "\"\($0)\"" } ?? "any"
            return CheckResult(provider: provider, need: need, status: .unknown, chosen: nil, alternatives: [],
                               message: "No \(provider.displayName) account \(which) is set up in Pitstop.")
        }

        let chosen = verdict(for: target, need: need)
        let alternatives = candidates
            .filter { $0.account.id != target.account.id }
            .map { verdict(for: $0, need: need) }
            .filter { $0.status == .go || $0.status == .tight }

        return CheckResult(provider: provider, need: need, status: chosen.status, chosen: chosen,
                           alternatives: alternatives,
                           message: message(provider: provider, need: need, verdict: chosen, alternatives: alternatives))
    }

    static func message(provider: ProviderKind, need: Need, verdict: AccountVerdict,
                        alternatives: [AccountVerdict]) -> String {
        let needs = [need.session.map { "\(percent($0)) session" }, need.weekly.map { "\(percent($0)) weekly" }]
            .compactMap { $0 }.joined(separator: ", ")
        let has = [verdict.sessionLeft.map { "\(percent($0)) session" }, verdict.weeklyLeft.map { "\(percent($0)) weekly" }]
            .compactMap { $0 }.joined(separator: ", ")
        let head = "\(provider.displayName) (\(verdict.account)): needs ~\(needs), has \(has.isEmpty ? "unknown" : has)."

        var tail: String
        switch verdict.status {
        case .go: tail = "Go."
        case .tight: tail = "Fits, but it's tight."
        case .wait:
            if let ready = verdict.readyAt {
                tail = "Wait until \(resetClock(ready)) (in \(countdown(to: ready)))."
            } else {
                tail = "Not enough left."
            }
        case .unknown: tail = "Couldn't check: \(verdict.problem ?? "unknown error")"
        case .split: tail = "Split this ticket."
        }
        if verdict.status != .go, !alternatives.isEmpty {
            tail += " \(alternatives.map(\.account).joined(separator: ", ")) has room now."
        }
        return "\(head) \(tail)"
    }
}
