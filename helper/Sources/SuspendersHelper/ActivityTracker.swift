import CoreGraphics
import Foundation
import SuspendersCore

/// Counts minutes of real keyboard/mouse activity each evening.
final class ActivityTracker {
    static let tickSeconds: TimeInterval = 30
    private let defaults = UserDefaults.standard
    private var config: Config

    init(config: Config) { self.config = config }

    func update(config: Config) { self.config = config }

    var idleSeconds: TimeInterval {
        // ~0 == "any input event"
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    var isActive: Bool { idleSeconds < config.idleThresholdSeconds }

    private func key(_ date: Date) -> String {
        "active-" + Schedule.nightKey(date, morning: config.morningTime)
    }

    var activeSecondsTonight: TimeInterval { defaults.double(forKey: key(Date())) }

    var activeMinutesTonight: Int { Int(activeSecondsTonight / 60) }

    /// Call every `tickSeconds`.
    func tick(now: Date = Date()) {
        guard Schedule.isWithin(now, from: config.eveningCountFrom, to: config.morningTime), isActive else { return }
        let k = key(now)
        defaults.set(defaults.double(forKey: k) + ActivityTracker.tickSeconds, forKey: k)
        if defaults.string(forKey: "active-last-key") != k {
            if let old = defaults.string(forKey: "active-last-key") { defaults.removeObject(forKey: old) }
            defaults.set(k, forKey: "active-last-key")
        }
    }
}
