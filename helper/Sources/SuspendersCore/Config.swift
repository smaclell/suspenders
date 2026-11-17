import Foundation

/// User configuration. Lives outside the repo in
/// ~/Library/Application Support/Suspenders/config.json.
public struct Config: Codable, Equatable {
    public var vaultPath: String?
    public var tags: [String] = ["nudge", "anki", "quote"]
    /// Tags whose notes are parsed as lists of quotes rather than passages.
    public var quoteTags: [String] = ["quote", "quotes"]
    public var port: UInt16 = 47615
    public var signOffTime: String = "22:00"
    public var windDownTime: String = "22:30"
    public var morningTime: String = "05:00"
    /// Tonight's active-time counter starts here.
    public var eveningCountFrom: String = "18:00"
    public var nudgeIntervalMinutes: Int = 15
    public var idleThresholdSeconds: Double = 120
    public var tintEnabled: Bool = true
    public var maxTintOpacity: Double = 0.35
    /// Relative to the vault (if set) or absolute. Leave nil to keep the log in Application Support.
    public var reasonsLogInVault: String? = nil

    public init() {}

    enum CodingKeys: String, CodingKey {
        case vaultPath, tags, quoteTags, port, signOffTime, windDownTime, morningTime, eveningCountFrom,
             nudgeIntervalMinutes, idleThresholdSeconds, tintEnabled, maxTintOpacity, reasonsLogInVault
    }

    // Tolerate partial files: any missing key falls back to its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        vaultPath = try c.decodeIfPresent(String.self, forKey: .vaultPath)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? d.tags
        quoteTags = try c.decodeIfPresent([String].self, forKey: .quoteTags) ?? d.quoteTags
        port = try c.decodeIfPresent(UInt16.self, forKey: .port) ?? d.port
        signOffTime = try c.decodeIfPresent(String.self, forKey: .signOffTime) ?? d.signOffTime
        windDownTime = try c.decodeIfPresent(String.self, forKey: .windDownTime) ?? d.windDownTime
        morningTime = try c.decodeIfPresent(String.self, forKey: .morningTime) ?? d.morningTime
        eveningCountFrom = try c.decodeIfPresent(String.self, forKey: .eveningCountFrom) ?? d.eveningCountFrom
        nudgeIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .nudgeIntervalMinutes) ?? d.nudgeIntervalMinutes
        idleThresholdSeconds = try c.decodeIfPresent(Double.self, forKey: .idleThresholdSeconds) ?? d.idleThresholdSeconds
        tintEnabled = try c.decodeIfPresent(Bool.self, forKey: .tintEnabled) ?? d.tintEnabled
        maxTintOpacity = try c.decodeIfPresent(Double.self, forKey: .maxTintOpacity) ?? d.maxTintOpacity
        reasonsLogInVault = try c.decodeIfPresent(String.self, forKey: .reasonsLogInVault)
    }

    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Suspenders", isDirectory: true)
    }

    public static var fileURL: URL { directory.appendingPathComponent("config.json") }

    public static func load() -> Config {
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        return config
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: Config.directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Config.fileURL, options: .atomic)
    }

    public var reasonsLogURL: URL {
        if let rel = reasonsLogInVault, !rel.isEmpty {
            if rel.hasPrefix("/") { return URL(fileURLWithPath: rel) }
            if let vault = vaultPath { return URL(fileURLWithPath: vault).appendingPathComponent(rel) }
        }
        return Config.directory.appendingPathComponent("late-night-reasons.md")
    }
}
