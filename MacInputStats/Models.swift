import Foundation

struct AppStats: Codable, Equatable {
    var keystrokes: Int = 0
    var pointerClicks: Int = 0
    var scrollEvents: Int = 0
    var talkDurationSeconds: Double = 0
    var screenTimeSeconds: Double = 0

    var formattedTalkTime: String {
        Self.formatDuration(talkDurationSeconds)
    }

    var formattedScreenTime: String {
        Self.formatDuration(screenTimeSeconds)
    }

    var totalInputs: Int {
        keystrokes + pointerClicks + scrollEvents
    }

    static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }
}

struct HourlyStats: Codable, Equatable {
    var keystrokes: Int = 0
    var pointerClicks: Int = 0
    var scrollEvents: Int = 0
    var talkDurationSeconds: Double = 0
}

struct DailyStats: Codable, Identifiable, Equatable {
    let date: String
    var keystrokes: Int = 0
    var pointerClicks: Int = 0
    var scrollEvents: Int = 0
    var talkDurationSeconds: Double = 0
    var perApp: [String: AppStats] = [:]
    var perHour: [String: HourlyStats] = [:]

    var id: String { date }

    init(date: String) {
        self.date = date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        keystrokes = try container.decodeIfPresent(Int.self, forKey: .keystrokes) ?? 0
        pointerClicks = try container.decodeIfPresent(Int.self, forKey: .pointerClicks) ?? 0
        scrollEvents = try container.decodeIfPresent(Int.self, forKey: .scrollEvents) ?? 0
        talkDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .talkDurationSeconds) ?? 0
        perApp = try container.decodeIfPresent([String: AppStats].self, forKey: .perApp) ?? [:]
        perHour = try container.decodeIfPresent([String: HourlyStats].self, forKey: .perHour) ?? [:]
    }

    var formattedTalkTime: String {
        AppStats.formatDuration(talkDurationSeconds)
    }

    private static let hiddenApps: Set<String> = ["loginwindow", ""]

    /// Top apps sorted by screen time, descending.
    var topApps: [(name: String, stats: AppStats)] {
        perApp
            .filter { !Self.hiddenApps.contains($0.key) }
            .map { (name: $0.key, stats: $0.value) }
            .sorted { $0.stats.screenTimeSeconds > $1.stats.screenTimeSeconds }
    }

    func stats(for category: AppCategory) -> AppStats {
        var combined = AppStats()
        for appName in category.appNames {
            if let s = perApp[appName] {
                combined.keystrokes += s.keystrokes
                combined.pointerClicks += s.pointerClicks
                combined.scrollEvents += s.scrollEvents
                combined.talkDurationSeconds += s.talkDurationSeconds
                combined.screenTimeSeconds += s.screenTimeSeconds
            }
        }
        return combined
    }
}

struct AppCategory: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var appNames: Set<String>

    init(name: String, appNames: Set<String> = []) {
        self.id = UUID()
        self.name = name
        self.appNames = appNames
    }
}
