import Foundation

public enum Schedule {
    /// "HH:MM" → minutes after midnight.
    public static func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m)
        else { return nil }
        return h * 60 + m
    }

    public static func minutesOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Is `date` within [start, end), wrapping past midnight if needed?
    public static func isWithin(_ date: Date, from start: String, to end: String, calendar: Calendar = .current) -> Bool {
        guard let s = minutes(start), let e = minutes(end), s != e else { return false }
        let t = minutesOfDay(date, calendar: calendar)
        return s < e ? (t >= s && t < e) : (t >= s || t < e)
    }

    /// Minutes since `start` if inside [start, end), else nil.
    public static func minutesSince(_ start: String, until end: String, at date: Date, calendar: Calendar = .current) -> Int? {
        guard isWithin(date, from: start, to: end, calendar: calendar), let s = minutes(start) else { return nil }
        let t = minutesOfDay(date, calendar: calendar)
        return t >= s ? t - s : t + 1440 - s
    }

    /// "2026-11-16" for any time between morning on the 16th and morning on the 17th.
    public static func nightKey(_ date: Date, morning: String, calendar: Calendar = .current) -> String {
        var d = date
        if let m = minutes(morning), minutesOfDay(date, calendar: calendar) < m {
            d = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
