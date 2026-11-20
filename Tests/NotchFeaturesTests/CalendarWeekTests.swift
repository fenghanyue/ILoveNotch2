// SPDX-License-Identifier: MIT
import Foundation
import Testing

@testable import NotchFeatures

@MainActor
struct CalendarWeekTests {
    @Test func eventsAndTasksFallOnTheDaysOfTheWeekTheyCover() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/London"))
        calendar.firstWeekday = 2  // Monday
        let wednesday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 15)))
        let days = CalendarFeature.week(of: wednesday, calendar: calendar)
        #expect(days.map { calendar.component(.day, from: $0) } == [16, 17, 18, 19, 20, 21, 22], "Monday to Sunday")
        func at(_ day: Int, _ hour: Double) -> Date { days[day] + hour * 3600 }
        let events = [
            DayEvent(id: "late", title: "Late show", start: at(1, 22), end: at(2, 1)),
            DayEvent(id: "midnight", title: "Until midnight", start: at(0, 23), end: at(1, 0)),
            DayEvent(id: "trip", title: "Trip", start: days[4], end: at(6, 0) - 1, isAllDay: true),
            DayEvent(id: "lunch", title: "Lunch", start: at(2, 12), end: at(2, 13)),
            DayEvent(id: "holiday", title: "Holiday", start: days[2], end: at(3, 0) - 1, isAllDay: true),
            DayEvent(id: "next week", title: "Next week", start: at(6, 33), end: at(6, 34)),
        ]
        let week = CalendarFeature.group(events, into: days, calendar: calendar)
        func ids(_ day: Int) -> [String] { week[days[day]]?.map(\.id) ?? [] }
        #expect(ids(0) == ["midnight"])
        #expect(ids(1) == ["late"], "an event ending at midnight isn't on the next day")
        #expect(ids(2) == ["holiday", "late", "lunch"], "over midnight it's on both days; all-day first")
        #expect(ids(3).isEmpty && ids(4) == ["trip"] && ids(5) == ["trip"] && ids(6).isEmpty)

        let tasks = [
            TaskItem(id: "overdue", title: "Overdue", due: days[0]),
            TaskItem(id: "wednesday", title: "Wednesday", due: at(2, 9), hasTime: true),
            TaskItem(id: "someday", title: "Someday"),
        ]
        let today = days[2]
        let due = CalendarFeature.tasks(tasks, on: today, today: today, calendar: calendar)
        #expect(due.map(\.id) == ["overdue", "wednesday"])
        // Any other day, after today or before it, shows what's overdue beside its own.
        let thursday = tasks + [TaskItem(id: "thursday", title: "Thursday", due: at(3, 10), hasTime: true)]
        let onThursday = CalendarFeature.tasks(thursday, on: days[3], today: today, calendar: calendar)
        #expect(onThursday.map(\.id) == ["overdue", "thursday"])
        #expect(CalendarFeature.tasks(tasks, on: days[1], today: today, calendar: calendar).map(\.id) == ["overdue"])

        // Next week's read keeps every task due in it and the latest overdue ones, at most
        // `dueTaskLimit`; what's due between today and that week, or never, shows on none of its days.
        let nextWeek = try #require(calendar.date(byAdding: .day, value: 7, to: days[0]))
        let pile = (1...25).map { TaskItem(id: "late \($0)", title: "Late", due: days[0] - Double($0) * 86_400) }
        let read = tasks + pile + [TaskItem(id: "next", title: "Next week", due: nextWeek + 3600, hasTime: true)]
        let kept = CalendarFeature.weekTasks(read, from: nextWeek, today: today, calendar: calendar)
        #expect(kept.count == CalendarFeature.dueTaskLimit + 1)
        #expect(kept.suffix(2).map(\.id) == ["overdue", "next"], "the latest overdue, then the week's")
        #expect(!kept.contains { ["wednesday", "someday", "late 25"].contains($0.id) })
    }

    @Test func aTimeWithoutADayLandsOnTheChosenDay() throws {
        let calendar = Calendar.current
        let chosen = try #require(calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: .now)))
        let lunch = try #require(CalendarFeature.draft("Lunch 1pm", on: chosen))
        #expect(lunch.title == "Lunch")
        #expect(lunch.start == calendar.date(bySettingHour: 13, minute: 0, second: 0, of: chosen))
        let named = try #require(CalendarFeature.draft("Lunch tomorrow 1pm for 1h", on: chosen))
        #expect(calendar.isDateInTomorrow(named.start) && named.duration == 3600, "a day it names stays")
        #expect(CalendarFeature.draft("Lunch", on: chosen) == nil, "an event still needs a time")
    }
}
