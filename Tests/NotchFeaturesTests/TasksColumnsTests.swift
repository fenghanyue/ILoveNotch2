// SPDX-License-Identifier: MIT
import Foundation
import Testing

@testable import NotchFeatures

@MainActor
struct TasksColumnsTests {
    @Test func theBoardGroupsByDayAndMovesKeepTheTime() throws {
        let calendar = Calendar.current
        let now = try #require(
            calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000)))
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, hour: Int? = nil) -> Date {
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            return hour.flatMap { calendar.date(bySettingHour: $0, minute: 0, second: 0, of: date) } ?? date
        }
        let tasks = TasksFeature(eventStore: EventStore(), defaults: UserDefaults(suiteName: "TC-\(UUID())")!)
        tasks.show(
            tasks: [
                TaskItem(id: "rent", title: "Pay rent", due: day(0, hour: 17), hasTime: true),
                TaskItem(id: "late", title: "Renew passport", due: day(-2)),
                TaskItem(id: "cleaning", title: "Dry cleaning", due: day(2, hour: 10), hasTime: true),
                TaskItem(id: "dentist", title: "Call the dentist", due: day(1, hour: 16), hasTime: true),
                TaskItem(id: "flights", title: "Book flights"),
            ],
            completed: [
                TaskItem(id: "haircut", title: "Book haircut", completed: now - 3600),
                TaskItem(id: "plants", title: "Water the plants", completed: now - 86_400 * 2),
            ])
        let columns = tasks.columns(now: now)
        #expect(columns.map(\.kind) == [.today, .upcoming, .done])
        #expect(columns[0].tasks.map(\.id) == ["late", "rent"], "overdue first")
        #expect(columns[1].runs.map(\.spot) == [.day(day(1)), .day(day(2)), .day(nil)], "by day, No date last")
        #expect(columns[2].tasks.map(\.id) == ["haircut"], "only what was finished today")
        #expect(tasks.progress(now: now) == (1, 3))

        // Upcoming keeps the time on the new day; Today drops a time already gone; No date clears it.
        let dentist = columns[1].tasks[0]
        let monday = TasksFeature.due(for: dentist, on: day(4), now: now)
        #expect(monday.due == day(4, hour: 16) && monday.hasTime)
        let gone = TasksFeature.due(for: dentist, on: today, now: day(0, hour: 17))
        #expect(gone.due == today && !gone.hasTime)
        #expect(TasksFeature.due(for: dentist, on: nil, now: now).due == nil)
        // Into Upcoming: tomorrow, or a day still ahead stays.
        #expect(tasks.upcomingSpot(for: columns[0].tasks[1], now: now) == .day(day(1)))
        #expect(tasks.upcomingSpot(for: columns[1].tasks[1], now: now) == .day(day(2)))

        // Dragged within a run: up lands where the target was, down after it. From another run it
        // lands before the target, and other runs keep their order.
        let open: Set<String> = ["a", "b", "c", "x", "n"]
        let run = ["a", "b", "c"]
        #expect(TasksFeature.arranged([], run: run, moving: "c", before: "a", open: open) == ["c", "a", "b"])
        #expect(TasksFeature.arranged([], run: run, moving: "a", before: "c", open: open) == ["b", "c", "a"])
        let joined = TasksFeature.arranged(["x"], run: ["a", "b"], moving: "n", before: "b", open: open)
        #expect(joined == ["x", "a", "n", "b"])
        tasks.move(columns[0].tasks[1], to: .today, before: columns[0].tasks[0], now: now)
        #expect(tasks.columns(now: now)[0].tasks.map(\.id) == ["rent", "late"], "your own order wins")
    }
}
