import AppKit
import SuspendersCore

/// Decides, every tick, which sign-off nudges should be active.
final class SignOffController {
    private var config: Config
    private let tracker: ActivityTracker
    private let tint = TintOverlay()
    private let windDown = WindDownWindow()
    private let log: (String, String) -> Void

    private var lastNudge: Date?
    private var nudgeIndex = 0
    private var windDownShownFor: String?
    private var windDownDeferredUntil: Date?
    private var deferrals = 0
    private(set) var snoozedUntil: Date?

    init(config: Config, tracker: ActivityTracker, log: @escaping (_ kind: String, _ text: String) -> Void) {
        self.config = config
        self.tracker = tracker
        self.log = log
    }

    func update(config: Config) { self.config = config }

    var minutesPastSignOff: Int? {
        Schedule.minutesSince(config.signOffTime, until: config.morningTime, at: Date())
    }

    var isSnoozed: Bool { (snoozedUntil ?? .distantPast) > Date() }

    func snooze(minutes: Int) {
        snoozedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        tint.hide()
        windDown.close()
    }

    func tick(now: Date = Date()) {
        guard let past = Schedule.minutesSince(config.signOffTime, until: config.morningTime, at: now) else {
            resetForDay()
            return
        }
        if isSnoozed { return }

        let active = tracker.isActive

        // 1. Gentle notifications while active.
        if active, lastNudge.map({ now.timeIntervalSince($0) >= Double(config.nudgeIntervalMinutes * 60) }) ?? true {
            let (title, body) = Notifier.nudges[nudgeIndex % Notifier.nudges.count]
            Notifier.send(title: title, body: body)
            nudgeIndex += 1
            lastNudge = now
        }

        // 2. Warm tint that deepens every interval.
        if config.tintEnabled {
            let steps = Double(past / max(1, config.nudgeIntervalMinutes))
            tint.show(opacity: min(config.maxTintOpacity, 0.07 + 0.045 * steps))
        }

        // 3. Wind-down card, once per night (re-shown after a deferral).
        let key = Schedule.nightKey(now, morning: config.morningTime)
        let windDownDue = Schedule.isWithin(now, from: config.windDownTime, to: config.morningTime)
        let deferralOver = windDownDeferredUntil.map { now >= $0 } ?? (windDownShownFor != key)
        if windDownDue, active, deferralOver, !windDown.isShowing {
            showWindDown()
            windDownShownFor = key
            windDownDeferredUntil = .distantFuture
        }
    }

    func showWindDown() {
        let f = DateFormatter()
        f.timeStyle = .short
        let mins = tracker.activeMinutesTonight
        let view = WindDownView(
            time: f.string(from: Date()),
            question: SignOffController.questions.randomElement()!,
            activeTonight: mins >= 60 ? "\(mins / 60)h \(mins % 60)m" : "\(mins) minutes",
            deferrals: deferrals,
            onSignOff: { [weak self] answer in
                guard let self else { return }
                if !answer.isEmpty { self.log("Reflection", answer) }
                self.windDown.close()
                SignOffController.sleepDisplay()
            },
            onDefer: { [weak self] answer in
                guard let self else { return }
                self.deferrals += 1
                self.log("Kept going", answer.isEmpty ? "(no reason given) — deferral #\(self.deferrals)" : answer)
                self.windDownDeferredUntil = Date().addingTimeInterval(15 * 60)
                self.windDown.close()
            })
        windDown.show(view: view)
    }

    private func resetForDay() {
        tint.hide()
        windDown.close()
        lastNudge = nil
        deferrals = 0
        windDownDeferredUntil = nil
        snoozedUntil = nil
    }

    static func sleepDisplay() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["displaysleepnow"]
        try? p.run()
    }

    static let questions = [
        "What's one good thing from today?",
        "What would make tomorrow morning easy?",
        "Who did you show up for today?",
        "What are you letting go of tonight?",
        "What's the first thing you'll do tomorrow?",
    ]
}
