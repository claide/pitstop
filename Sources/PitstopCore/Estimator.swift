import Foundation

public enum TicketSize: String, Codable, CaseIterable, Sendable {
    case light, normal, heavy

    public var multiplier: Double {
        switch self {
        case .light: return 0.75
        case .normal: return 1
        case .heavy: return 1.5
        }
    }
}

/// How much of each window a ticket of this many story points needs (normal size).
public struct EstimateRow: Codable, Sendable {
    public var points: Double
    public var session: Double
    public var weekly: Double

    public init(points: Double, session: Double, weekly: Double) {
        self.points = points
        self.session = session
        self.weekly = weekly
    }
}

public struct Need: Codable, Sendable {
    public var session: Double?
    public var weekly: Double?

    public init(session: Double?, weekly: Double?) {
        self.session = session
        self.weekly = weekly
    }

    /// Parses "session:40,weekly:8".
    public static func parse(_ text: String) -> Need? {
        var need = Need(session: nil, weekly: nil)
        for part in text.split(separator: ",") {
            let pair = part.split(separator: ":")
            guard pair.count == 2, let value = Double(pair[1]) else { return nil }
            switch pair[0].lowercased() {
            case "session": need.session = value
            case "weekly": need.weekly = value
            default: return nil
            }
        }
        return (need.session == nil && need.weekly == nil) ? nil : need
    }
}

public enum Estimator {
    /// Starting guesses. Replaced by `pitstop calibrate --apply` after 10 real tickets.
    public static let defaultTable: [EstimateRow] = [
        EstimateRow(points: 1, session: 10, weekly: 2),
        EstimateRow(points: 2, session: 15, weekly: 3),
        EstimateRow(points: 3, session: 25, weekly: 5),
        EstimateRow(points: 5, session: 40, weekly: 8),
        EstimateRow(points: 8, session: 65, weekly: 13),
    ]

    /// Above this many points, Pitstop recommends splitting the ticket.
    public static let splitAbove: Double = 8

    public static var isCalibrated: Bool {
        FileManager.default.fileExists(atPath: PitstopPaths.estimateTable.path)
    }

    public static func table() -> [EstimateRow] {
        if let data = try? Data(contentsOf: PitstopPaths.estimateTable),
           let rows = try? JSONDecoder().decode([EstimateRow].self, from: data), !rows.isEmpty {
            return rows.sorted { $0.points < $1.points }
        }
        return defaultTable
    }

    public static func saveTable(_ rows: [EstimateRow]) throws {
        try PitstopJSON.encoder.encode(rows.sorted { $0.points < $1.points })
            .write(to: PitstopPaths.estimateTable, options: .atomic)
    }

    /// nil means the ticket is too big and should be split.
    public static func need(points: Double, size: TicketSize) -> Need? {
        guard points <= splitAbove else { return nil }
        let rows = table()
        guard let row = rows.first(where: { $0.points >= points }) ?? rows.last else { return nil }
        return Need(session: roundUp(row.session * size.multiplier, to: 5),
                    weekly: roundUp(row.weekly * size.multiplier, to: 1))
    }

    static func roundUp(_ value: Double, to step: Double) -> Double {
        (value / step).rounded(.up) * step
    }
}
