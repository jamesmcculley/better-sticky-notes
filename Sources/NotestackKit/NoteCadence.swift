import Foundation

enum NoteCadence {
    static let dailyStack = "Daily"
    static let weeklyStack = "Weekly"

    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX") // machine-readable: never the user's locale
        formatter.timeZone = .current
        return formatter
    }()

    private static let dayTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d, yyyy"
        formatter.timeZone = .current
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.timeZone = .current
        return formatter
    }()

    private static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        calendar.timeZone = .current
        return calendar
    }()

    static func dayFilename(for date: Date) -> String {
        filenameFormatter.string(from: date) + ".md"
    }

    static func dayTitle(for date: Date) -> String {
        dayTitleFormatter.string(from: date)
    }

    static func date(fromFilename filename: String) -> Date? {
        guard filename.hasSuffix(".md") else { return nil }
        return filenameFormatter.date(from: String(filename.dropLast(3)))
    }

    static func weekStart(containing date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    static func weekFilename(for date: Date) -> String {
        dayFilename(for: weekStart(containing: date))
    }

    static func weekTitle(for date: Date) -> String {
        "Week of " + shortDateFormatter.string(from: weekStart(containing: date))
    }

    static func shortDayLabel(for date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    static func shortWeekLabel(for date: Date) -> String {
        "Week of " + shortDateFormatter.string(from: weekStart(containing: date))
    }
}

enum NotePeriod: String, CaseIterable {
    case daily, weekly

    var stack: String { self == .daily ? NoteCadence.dailyStack : NoteCadence.weeklyStack }
    var stepDays: Int { self == .daily ? 1 : 7 }
    func filename(for date: Date) -> String {
        self == .daily ? NoteCadence.dayFilename(for: date) : NoteCadence.weekFilename(for: date)
    }
    func title(for date: Date) -> String {
        self == .daily ? NoteCadence.dayTitle(for: date) : NoteCadence.weekTitle(for: date)
    }
    func rollover(viewingID: String, previousDate: Date, now: Date) -> String {
        viewingID == filename(for: previousDate) ? filename(for: now) : viewingID
    }
}
