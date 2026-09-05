import Foundation

struct UsageWindow: Identifiable, Equatable, Sendable {
    let id: String
    let usedPercent: Int
    let durationMinutes: Int?
    let resetsAt: Date?

    var remainingPercent: Int {
        min(100, max(0, 100 - usedPercent))
    }

    var durationLabel: String {
        DurationLabel.format(minutes: durationMinutes)
    }
}

struct UsageSnapshot: Equatable, Sendable {
    let planType: String?
    let windows: [UsageWindow]
    let fetchedAt: Date
}

enum DurationLabel {
    static func format(minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "Limit" }
        if minutes.isMultiple(of: 1_440) {
            return "\(minutes / 1_440)d"
        }
        if minutes.isMultiple(of: 60) {
            return "\(minutes / 60)h"
        }
        return "\(minutes)m"
    }
}

enum ResetText {
    static func relative(to date: Date, now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Resets \(formatter.localizedString(for: date, relativeTo: now))"
    }

    static func absolute(
        _ date: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        var calendar = calendar
        calendar.timeZone = timeZone

        let time = DateFormatter()
        time.locale = locale
        time.timeZone = timeZone
        time.dateStyle = .none
        time.timeStyle = .short

        if calendar.isDateInToday(date) {
            return "Today at \(time.string(from: date))"
        }
        if calendar.isDateInTomorrow(date) {
            return "Tomorrow at \(time.string(from: date))"
        }

        let full = DateFormatter()
        full.locale = locale
        full.timeZone = timeZone
        full.setLocalizedDateFormatFromTemplate("EEE d MMM HHmm")
        return full.string(from: date)
    }
}

enum FreshnessText {
    static func format(_ date: Date, now: Date = .now, stale: Bool = false) -> String {
        let suffix = stale ? " · stale" : ""
        if abs(date.timeIntervalSince(now)) < 5 {
            return "Updated just now\(suffix)"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: date, relativeTo: now))\(suffix)"
    }
}

enum UsageError: LocalizedError, Equatable {
    case chatGPTNotInstalled
    case untrustedChatGPTApp
    case codexExecutableMissing
    case appServerStopped
    case notSignedIn(String?)
    case incompatibleResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .chatGPTNotInstalled:
            "ChatGPT is not installed."
        case .untrustedChatGPTApp:
            "The discovered ChatGPT app is not signed by OpenAI."
        case .codexExecutableMissing:
            "The installed ChatGPT app does not contain Codex."
        case .appServerStopped:
            "The Codex connection stopped unexpectedly."
        case .notSignedIn(let message):
            message ?? "Open ChatGPT and sign in to view your limits."
        case .incompatibleResponse:
            "ChatGPT returned an unsupported usage response."
        case .server(let message):
            message
        }
    }
}

protocol RateLimitProviding: Sendable {
    var updates: AsyncStream<UsageSnapshot> { get }
    func read() async throws -> UsageSnapshot
    func stop() async
}
