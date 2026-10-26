import Foundation

public struct MarkUsage: Codable, Sendable {
    public let accountId: String
    public let accountName: String
    public let provider: ProviderKind
    public let sessionUsed: Double?
    public let sessionResetsAt: Date?
    public let weeklyUsed: Double?
    public let weeklyResetsAt: Date?

    public init(_ snapshot: AccountSnapshot) {
        accountId = snapshot.account.id
        accountName = snapshot.account.name
        provider = snapshot.account.provider
        sessionUsed = snapshot.window(.session)?.usedPercent
        sessionResetsAt = snapshot.window(.session)?.resetsAt
        weeklyUsed = snapshot.window(.weekly)?.usedPercent
        weeklyResetsAt = snapshot.window(.weekly)?.resetsAt
    }
}

public struct TicketMark: Codable, Sendable {
    public let ticket: String
    public let phase: String          // "start" or "end"
    public let at: Date
    public let points: Double?
    public let size: TicketSize?
    public let usage: [MarkUsage]

    public init(ticket: String, phase: String, points: Double?, size: TicketSize?, snapshots: [AccountSnapshot]) {
        self.ticket = ticket.uppercased()
        self.phase = phase
        self.at = .now
        self.points = points
        self.size = size
        self.usage = snapshots.filter { $0.error == nil }.map(MarkUsage.init)
    }
}

public struct TicketCost: Codable, Sendable {
    public let ticket: String
    public let points: Double?
    public let size: TicketSize?
    public let account: String
    public let session: Double
    public let weekly: Double?
}

/// A ticket with marks that can't be turned into a cost, and why.
public struct SkippedTicket: Codable, Sendable {
    public let ticket: String
    public let reason: String
}

/// What `pitstop report` prints: either `cost` or `skipped` is set.
public struct TicketReport: Codable, Sendable {
    public let ticket: String
    public let cost: TicketCost?
    public let skipped: String?

    public init(ticket: String, cost: TicketCost?, skipped: String?) {
        self.ticket = ticket
        self.cost = cost
        self.skipped = skipped
    }
}

public enum TicketMeasurement: Sendable {
    case measured(TicketCost)
    case skipped(String)
}

public enum TicketLog {
    static let sessionLength: TimeInterval = 5 * 3_600
    static let weeklyLength: TimeInterval = 7 * 86_400

    public static func append(_ mark: TicketMark) throws {
        var data = try PitstopJSON.lineEncoder.encode(mark)
        data.append(0x0A)
        let url = PitstopPaths.tickets
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
    }

    public static func marks() -> [TicketMark] {
        guard let text = try? String(contentsOf: PitstopPaths.tickets, encoding: .utf8) else { return [] }
        let decoder = PitstopJSON.decoder
        return text.split(separator: "\n").compactMap { try? decoder.decode(TicketMark.self, from: Data($0.utf8)) }
    }

    /// Actual usage per finished ticket.
    public static func costs() -> [TicketCost] { outcomes().costs }

    /// Every ticket in the log: the ones with a usable cost, and the ones skipped with a reason.
    public static func outcomes() -> (costs: [TicketCost], skipped: [SkippedTicket]) {
        var costs: [TicketCost] = []
        var skipped: [SkippedTicket] = []
        for (ticket, marks) in Dictionary(grouping: marks(), by: \.ticket) {
            switch measure(ticket: ticket, marks: marks) {
            case .measured(let cost): costs.append(cost)
            case .skipped(let reason): skipped.append(SkippedTicket(ticket: ticket, reason: reason))
            }
        }
        return (costs.sorted { $0.ticket < $1.ticket }, skipped.sorted { $0.ticket < $1.ticket })
    }

    /// Turns one ticket's marks into a cost, using the last end and the last start before it.
    /// Tickets that crossed a reset are skipped, because the before/after numbers belong to
    /// different windows.
    public static func measure(ticket: String, marks: [TicketMark]) -> TicketMeasurement {
        guard let end = marks.last(where: { $0.phase == "end" }) else {
            return .skipped("not finished yet (no end mark)")
        }
        guard let start = marks.last(where: { $0.phase == "start" && $0.at < end.at }) else {
            return .skipped("no start mark before the end mark")
        }
        guard !start.usage.isEmpty, !end.usage.isEmpty else {
            return .skipped("usage couldn't be read when the \(start.usage.isEmpty ? "start" : "end") was marked")
        }

        var best: TicketCost?
        var sharedAccount = false
        var crossedReset = false
        for before in start.usage {
            guard let after = end.usage.first(where: { $0.accountId == before.accountId }) else { continue }
            sharedAccount = true
            guard let s0 = before.sessionUsed, let s1 = after.sessionUsed else { continue }
            guard comparable(before.sessionResetsAt, used: s0, after.sessionResetsAt,
                             startedAt: start.at, windowLength: sessionLength) else {
                crossedReset = true
                continue
            }
            let session = s1 - s0
            guard session > 0 else { continue }

            var weekly: Double?
            if let w0 = before.weeklyUsed, let w1 = after.weeklyUsed,
               comparable(before.weeklyResetsAt, used: w0, after.weeklyResetsAt,
                          startedAt: start.at, windowLength: weeklyLength) {
                weekly = max(0, w1 - w0)
            }
            if session > (best?.session ?? 0) {
                best = TicketCost(ticket: ticket, points: start.points ?? end.points,
                                  size: start.size ?? end.size, account: after.accountName,
                                  session: session, weekly: weekly)
            }
        }

        if let best { return .measured(best) }
        if !sharedAccount { return .skipped("start and end were recorded for different accounts") }
        if crossedReset { return .skipped("crossed a limit reset, so start and end can't be compared") }
        return .skipped("no measurable session usage between start and end")
    }

    /// Whether usage at the start and end mark can be subtracted.
    /// - Same reset time: the same window, so yes.
    /// - Nothing used and no reset time at the start: the window hadn't opened yet. That's fine
    ///   as long as the window open at the end began after the start mark.
    private static func comparable(_ before: Date?, used: Double, _ after: Date?,
                                   startedAt: Date, windowLength: TimeInterval) -> Bool {
        if sameWindow(before, after) { return true }
        if before == nil, used == 0, let after {
            return after.addingTimeInterval(-windowLength) >= startedAt.addingTimeInterval(-300)
        }
        return false
    }

    private static func sameWindow(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return false }
        return abs(a.timeIntervalSince(b)) < 300
    }

    /// Averages real costs per story-point value, normalised to "normal" size.
    /// Point values without data keep their current table row.
    public static func calibratedTable(from costs: [TicketCost]) -> [EstimateRow] {
        var rows = Dictionary(uniqueKeysWithValues: Estimator.table().map { ($0.points, $0) })
        for (points, group) in Dictionary(grouping: costs.filter { $0.points != nil }, by: { $0.points! }) {
            let sessions = group.map { $0.session / ($0.size ?? .normal).multiplier }
            let weeklies = group.compactMap { cost in cost.weekly.map { $0 / (cost.size ?? .normal).multiplier } }
            let session = Estimator.roundUp(sessions.reduce(0, +) / Double(sessions.count), to: 5)
            let weekly = weeklies.isEmpty
                ? (rows[points]?.weekly ?? 0)
                : Estimator.roundUp(weeklies.reduce(0, +) / Double(weeklies.count), to: 1)
            rows[points] = EstimateRow(points: points, session: session, weekly: weekly)
        }
        return rows.values.sorted { $0.points < $1.points }
    }
}
