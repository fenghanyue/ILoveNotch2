// SPDX-License-Identifier: MIT
import AppKit
import NotchTheme
import SwiftUI
import Testing

@testable import NotchFeatures

/// A task opened in full on the board, as Calendar's click reveals it, and Calendar on a day other
/// than today with its tasks card. Always checks that they draw; with SNAPSHOT_DIR set, also writes
/// PNGs there, at the default size and the smallest, in AUDIT_THEME (Black without it).
@MainActor
struct TaskDetailSnapshotTests {
    @Test func aRevealedTaskOpensInFull() throws {
        let now = Date.now
        let today = Calendar.current.startOfDay(for: now)
        func day(_ offset: Int, hour: Int? = nil) -> Date {
            let date = Calendar.current.date(byAdding: .day, value: offset, to: today)!
            return hour.flatMap { Calendar.current.date(bySettingHour: $0, minute: 30, second: 0, of: date) } ?? date
        }
        let renders = [
            ("tasks-revealed", "4", CGSize(width: 428, height: 200)),
            ("tasks-revealed-smallest", "5", CGSize(width: 350, height: 102)),
            ("tasks-revealed-tall", "5", CGSize(width: 428, height: 320)),
        ]
        for (name, id, size) in renders {
            let tasks = TasksFeature(eventStore: EventStore(), defaults: UserDefaults(suiteName: "TD-\(UUID())")!)
            tasks.show(
                tasks: [
                    TaskItem(id: "1", title: "Send the invoice", due: day(-1)),
                    TaskItem(id: "2", title: "Book flights", due: day(1, hour: 9), hasTime: true),
                    TaskItem(id: "3", title: "Call the dentist", due: day(2)),
                    TaskItem(
                        id: "4", title: "Water the plants on the balcony", due: day(3, hour: 8), hasTime: true,
                        listTitle: "Home", notes: "The ferns twice."),
                    TaskItem(
                        id: "5", title: "Renew the passport before the trip to Lisbon in March",
                        due: day(4, hour: 15), hasTime: true, priority: .medium, listTitle: "Errands",
                        notes: "Two photos, the old passport, and the form from the post office."),
                ],
                completed: [])
            // Low in Upcoming, below the fold: the column scrolls to it.
            tasks.reveal(id)
            try render(TasksView(tasks: tasks), name: name, size: size)
            #expect(tasks.revealing == nil, "the board took it")
        }
    }

    @Test func anotherDayKeepsItsTasksCard() throws {
        let calendar = CalendarFeature(eventStore: EventStore(), defaults: UserDefaults(suiteName: "TD-\(UUID())")!)
        let today = Calendar.current.startOfDay(for: .now)
        let later = try #require(Calendar.current.date(byAdding: .day, value: 2, to: today))
        calendar.select(later)
        calendar.show(
            events: [
                DayEvent(
                    id: "1", title: "Dentist", start: later + 10 * 3600, end: later + 11 * 3600,
                    color: RGB(red: 0.3, green: 0.6, blue: 1))
            ],
            dueTasks: [
                TaskItem(id: "2", title: "Send the invoice", due: today - 86_400),
                TaskItem(id: "3", title: "Pay rent", due: today),  // due today: not on another day
                TaskItem(id: "4", title: "Pick up the dry cleaning", due: later + 17 * 3600, hasTime: true),
            ])
        #expect(calendar.dueTasks.map(\.id) == ["2", "4"], "the overdue one, then the day's")
        let size = CGSize(width: 428, height: 200)
        try render(CalendarView(calendar: calendar), name: "calendar-later", size: size)
        calendar.show(events: [], dueTasks: [])
        try render(CalendarView(calendar: calendar), name: "calendar-later-empty", size: size)
    }

    /// Lays the view out in the theme's notch, lets what it does on appearing settle, and draws it.
    private func render(_ view: some View, name: String, size: CGSize) throws {
        let theme = Themes.theme(ProcessInfo.processInfo.environment["AUDIT_THEME"] ?? "black")
        let notch =
            view
            .frame(width: size.width, height: size.height)
            .padding(16)
            .background(theme.surface.color.color)
            .foregroundStyle(.themeInk)
            .environment(\.colorScheme, theme.appearance.colorScheme)
            .environment(\.theme, theme)
            .transaction { $0.animation = nil }
        let host = NSHostingView(rootView: notch)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: size.width + 32, height: size.height + 32),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: .now + 0.2)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0)
        if let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])?.write(
                to: URL(filePath: directory).appending(path: "\(name).png"))
        }
    }
}
