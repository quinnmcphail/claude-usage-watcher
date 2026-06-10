import Foundation

/// App settings persisted as JSON at
/// ~/Library/Application Support/ClaudeUsageWatcher/settings.json.
/// Loaded tolerantly (missing keys keep defaults); saved best-effort.
struct Settings: Codable {
    var notificationsEnabled = true
    var expanded = false
    var notifyWarnAt: Double = 80
    var notifyCriticalAt: Double = 95

    enum CodingKeys: String, CodingKey {
        case notificationsEnabled
        case expanded
        case notifyWarnAt
        case notifyCriticalAt
    }

    init() {}

    init(from decoder: Decoder) throws {
        // Tolerant decode: a missing or wrong-typed key keeps its default.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        notificationsEnabled = (try? c.decode(Bool.self, forKey: .notificationsEnabled)) ?? defaults.notificationsEnabled
        expanded = (try? c.decode(Bool.self, forKey: .expanded)) ?? defaults.expanded
        notifyWarnAt = (try? c.decode(Double.self, forKey: .notifyWarnAt)) ?? defaults.notifyWarnAt
        notifyCriticalAt = (try? c.decode(Double.self, forKey: .notifyCriticalAt)) ?? defaults.notifyCriticalAt
    }

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("ClaudeUsageWatcher", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL),
              let loaded = try? JSONDecoder().decode(Settings.self, from: data) else {
            return Settings()
        }
        return loaded
    }

    func save() {
        let url = Settings.fileURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: url)
        } catch {
            // best-effort; ignore failures
        }
    }
}
