import SwiftUI

/// A persistent child sticky; selecting a destination updates the main window immediately.
struct NavigatorView: View {
    let date: Date
    let period: NotePeriod
    var onDate: (Date, NotePeriod) -> Void
    var onLogbook: () -> Void
    var onChooseNotesFolder: () -> Void
    var onClose: () -> Void
    @State private var month: Date?
    private let calendar = Calendar.current
    private var visibleMonth: Date { calendar.dateInterval(of: .month, for: month ?? date)!.start }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Go to").font(.headline)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .accessibilityLabel("Close navigator")
            }
            HStack {
                periodButton("Daily", .daily)
                periodButton("Weekly", .weekly)
            }
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next month")
            }
            if period == .weekly {
                VStack(spacing: 6) {
                    ForEach(weeksInMonth, id: \.self) { week in
                        Button { onDate(week, .weekly) } label: {
                            Text(NoteCadence.weekTitle(for: week))
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(7)
                                .background(NoteCadence.weekFilename(for: week) == NoteCadence.weekFilename(for: date) ? Theme.neutralGlow.opacity(0.3) : Theme.paneBase.opacity(0), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(0..<7, id: \.self) { offset in
                    Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + offset) % 7])
                        .font(.caption).foregroundStyle(Theme.textDim)
                }
                ForEach(0..<42, id: \.self) { offset in
                    let day = cellDate(offset)
                    Button { onDate(day, .daily) } label: {
                        Text("\(calendar.component(.day, from: day))")
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .foregroundStyle(calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month) ? Theme.textPrimary : Theme.textDim)
                            .background(calendar.isDate(day, inSameDayAs: date) ? Theme.neutralGlow.opacity(0.3) : Theme.paneBase.opacity(0), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                }
            }
            }
            HStack {
                Button("Today") { month = nil; onDate(Date(), .daily) }
                Spacer()
                Button("This Week") { month = nil; onDate(Date(), .weekly) }
                Spacer()
                Button("Logbook", action: onLogbook)
            }.foregroundStyle(Theme.neutralGlow)
            Button("Choose Notes Folder…", action: onChooseNotesFolder)
                .font(.caption)
                .foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textPrimary)
        .padding(14)
        .frame(width: 270)
        .background(Theme.paneBase, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.neutralGlow, lineWidth: 1.25))
    }

    private func periodButton(_ title: String, _ value: NotePeriod) -> some View {
        Button { onDate(date, value) } label: {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(6)
                .background(period == value ? Theme.neutralGlow.opacity(0.3) : Theme.paneBase.opacity(0), in: RoundedRectangle(cornerRadius: 5))
        }
    }

    private var weeksInMonth: [Date] {
        let start = NoteCadence.weekStart(containing: visibleMonth)
        let end = calendar.date(byAdding: .month, value: 1, to: visibleMonth)!
        return (0..<6).compactMap { offset in
            guard let week = calendar.date(byAdding: .day, value: offset * 7, to: start), week < end else { return nil }
            return week
        }
    }

    private func shiftMonth(_ amount: Int) {
        month = calendar.date(byAdding: .month, value: amount, to: visibleMonth)
    }

    private func cellDate(_ offset: Int) -> Date {
        let leading = (calendar.component(.weekday, from: visibleMonth) - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: offset - leading, to: visibleMonth)!
    }
}
