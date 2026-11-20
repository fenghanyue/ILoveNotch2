// SPDX-License-Identifier: MIT
import AppKit
import NotchTheme
import SwiftUI
import Testing

@testable import NotchFeatures

@MainActor
struct NetworkLedgerTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "NetworkLedger-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Friday 20 November 2026, in weeks that start on Monday: each page is a calendar period, the
    /// days still to come are empty slots, and what's still in memory counts toward today but stays
    /// off yesterday's page.
    @Test func pagesAreCalendarPeriodsAndTotalsCountFromTheirStart() throws {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        func date(_ month: Int, _ day: Int, _ hour: Int = 0) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)))
        }
        let now = try date(11, 20, 15)
        let week = try #require(HistoryRange.week.interval(page: 0, now: now, calendar: calendar))
        let month = try #require(HistoryRange.month.interval(page: 0, now: now, calendar: calendar))
        #expect(HistoryRange.day.interval(page: 0, now: now, calendar: calendar)?.start == (try date(11, 20)))
        #expect(week == DateInterval(start: try date(11, 16), end: try date(11, 23)))
        #expect(HistoryRange.week.interval(page: -2, now: now, calendar: calendar)?.start == (try date(11, 2)))
        #expect(HistoryRange.month.interval(page: -1, now: now, calendar: calendar)?.start == (try date(10, 1)))
        #expect(HistoryRange.year.interval(page: 0, now: now, calendar: calendar)?.start == (try date(1, 1)))

        // An hour a day at 10 AM since 30 October, 1 KB down and 100 bytes up each.
        let history = NetworkHistory(url: folder.appending(path: "network.sqlite"))
        var hours: [Date: Traffic] = [:]
        for day in 0..<22 {
            hours[try #require(calendar.date(byAdding: .day, value: -day, to: try date(11, 20, 10)))] = Traffic(
                down: 1_000, up: 100)
        }
        history.add(hours)
        #expect(history.traffic(in: week) == Traffic(down: 5_000, up: 500), "Monday to Friday")
        #expect(history.traffic(in: month).down == 20_000, "since the 1st")
        let days = history.buckets(for: .week, in: week, now: now, calendar: calendar)
        #expect(try days.map(\.start) == (16...22).map { try date(11, $0) })
        #expect(days.map(\.traffic.down) == [1_000, 1_000, 1_000, 1_000, 1_000, 0, 0])
        #expect(days.map(\.upcoming) == [false, false, false, false, false, true, true])
        #expect(history.buckets(for: .month, in: month, now: now, calendar: calendar).count == 30)
        #expect(history.earliest() == (try date(10, 30, 10)))

        var counters = ["en0": Traffic()]
        let network = NetworkFeature(
            defaults: UserDefaults(suiteName: "NetworkLedger.\(UUID().uuidString)")!,
            storeURL: folder.appending(path: "live.sqlite"), netSpeedURL: nil, readCounters: { counters })
        network.receive(counters, at: .now - 2)
        counters["en0"] = Traffic(down: 7_000, up: 700)
        network.receive(counters, at: .now - 1)
        network.phase = .foreground
        #expect(network.soFar(.day) == Traffic(down: 7_000, up: 700))
        #expect(network.soFar(.month) == Traffic(down: 7_000, up: 700))
        #expect(network.buckets.reduce(Traffic()) { $0 + $1.traffic } == Traffic(down: 7_000, up: 700))
        network.page = -1
        #expect(network.buckets.allSatisfy { $0.traffic.total == 0 && !$0.upcoming }, "yesterday")
        network.range = .week
        #expect(network.page == 0, "a new range opens on now's page")
        network.phase = .stopped
    }

    /// The last minute's graph in the ledger's place. With SNAPSHOT_DIR set, writes network-minute.png
    /// and its -smallest copy there; AUDIT_THEME picks the theme, as in FeatureSnapshotTests.
    @Test func theMinutesGraphInTheLedgersPlace() throws {
        var counters = ["en0": Traffic()]
        let network = NetworkFeature(
            defaults: UserDefaults(suiteName: "NetworkLedger.\(UUID().uuidString)")!,
            storeURL: folder.appending(path: "network.sqlite"), netSpeedURL: nil, readCounters: { counters })
        let now = Date.now
        for second in stride(from: 60, through: 0, by: -1) {
            let ramp = min(1, Double(60 - second) / 25)
            counters["en0"]?.down += Int64(24_000_000 * ramp * (0.85 + 0.15 * sin(Double(second))))
            counters["en0"]?.up += Int64(900_000 + 500_000 * abs(sin(Double(second) / 3)))
            network.receive(counters, at: now - TimeInterval(second))
        }
        network.phase = .foreground
        try render(NetworkView(network: network, minute: true), name: "network-minute")
        network.phase = .stopped
    }

    // A copy of FeatureSnapshotTests' renderer, so this file stays the Network tab's own.

    private func render(_ view: some View, name: String) throws {
        let theme = Themes.theme(ProcessInfo.processInfo.environment["AUDIT_THEME"] ?? "black")
        for (size, suffix) in [(CGSize(width: 428, height: 200), ""), (CGSize(width: 350, height: 102), "-smallest")] {
            let host = NSHostingView(
                rootView:
                    view
                    .frame(width: size.width, height: size.height)
                    .padding(16)
                    .background(theme.surface.color.color)
                    .foregroundStyle(.themeInk)
                    .environment(\.colorScheme, theme.appearance.colorScheme)
                    .environment(\.theme, theme))
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: size.width + 32, height: size.height + 32),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            #expect(bitmap.pixelsWide > 0)
            if let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] {
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                try bitmap.representation(using: .png, properties: [:])?.write(
                    to: URL(filePath: directory).appending(path: "\(name)\(suffix).png"))
            }
        }
    }
}
