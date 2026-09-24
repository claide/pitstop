import Foundation

public func countdown(to date: Date, from now: Date = .now) -> String {
    let s = max(0, Int(date.timeIntervalSince(now)))
    let d = s / 86_400, h = (s % 86_400) / 3_600, m = (s % 3_600) / 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

/// "3:40 PM" within a day, "Sat 3:40 PM" further out.
public func resetClock(_ date: Date, now: Date = .now) -> String {
    date.timeIntervalSince(now) < 86_400
        ? date.formatted(date: .omitted, time: .shortened)
        : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
}

public func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }
