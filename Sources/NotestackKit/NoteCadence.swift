import Foundation

/// Filename/title conventions for the two fixed stacks Daily/Weekly notes live in (ADR 0019).
/// Both stacks reuse the exact same `NotesStore` directory-per-stack mechanism Stacks always used
/// (`NotesStore.directory(for:)`) -- "Daily" and "Weekly" are just two more stack names, not a new
/// storage concept. A day's file is always named after its own calendar date; a week's file is
/// always named after the Monday that starts it -- both `yyyy-MM-dd.md`, sorting correctly as
/// plain filenames with no extra parsing needed (reverse-chronological is just "sort the
/// filenames and reverse"). The two stacks never collide with each other (different directories),
/// so there's no need to decorate the week filename to tell it apart from a day's.
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

    /// Monday-start weeks (ISO-ish, but not strictly ISO week numbering -- this only ever needs
    /// "which 7-day block does this date fall in," never a week *number*).
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

    /// Parses a day or week file's own date back out of its filename -- used to sort the
    /// sidebar's historical lists and to detect the day/week rollover in `AppController`. Returns
    /// nil for anything that isn't one of this convention's own filenames (shouldn't happen for a
    /// file this app wrote, but a hand-added file in the same folder shouldn't crash anything).
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

    /// Short form for sidebar history rows, where the pinned "Today"/"This Week" rows already
    /// cover the full-length version.
    static func shortDayLabel(for date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    static func shortWeekLabel(for date: Date) -> String {
        "Week of " + shortDateFormatter.string(from: weekStart(containing: date))
    }
}

/// Daily and weekly notes can share a filename, so navigation identity includes cadence.
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
