// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import NotchTheme
import SwiftUI
import Testing

@testable import NotchFeatures

/// Renders the Home tab's bento with sample data inside a notch-sized panel, in Black or the theme
/// AUDIT_THEME names: at the snapshots' usual size, the default notch's (narrow), the smallest, and the
/// mock's (large). Always checks that it draws; with SNAPSHOT_DIR set, also writes PNGs there.
@MainActor
struct HomeSnapshotTests {
    private static let sizes: [(suffix: String, size: CGSize)] = [
        ("", CGSize(width: 428, height: 200)), ("-narrow", CGSize(width: 384, height: 184)),
        ("-smallest", CGSize(width: 350, height: 102)), ("-large", CGSize(width: 600, height: 256)),
    ]
    private let theme = Themes.theme(ProcessInfo.processInfo.environment["AUDIT_THEME"] ?? "black")

    @Test func everyCard() throws {
        let now = Date.now
        let media = MediaFeature(bundle: Bundle(for: HomeSnapshotMarker.self))
        media.receive(
            NowPlaying(
                title: "Slow Light", artist: "Juniper Coast", album: "Low Tide", isPlaying: true, duration: 231,
                elapsed: 108, timestamp: now, artwork: Self.sampleArtwork(), appBundleID: "com.apple.Music"))
        let calendar = CalendarFeature(eventStore: EventStore(), defaults: UserDefaults(suiteName: "HC-\(UUID())")!)
        calendar.show(events: [
            DayEvent(
                id: "1", title: "Design review", start: now + 18 * 60, end: now + 48 * 60,
                color: RGB(red: 0.35, green: 0.63, blue: 1),
                meeting: MeetingLink(URL(string: "https://meet.google.com/abc-defg-hij")!))
        ])
        let tasks = TasksFeature(eventStore: EventStore(), defaults: UserDefaults(suiteName: "HT-\(UUID())")!)
        tasks.show(
            tasks: [
                TaskItem(id: "1", title: "Send invoice", due: now - 1800, hasTime: true),
                TaskItem(id: "2", title: "Answer review", due: now + 1800, hasTime: true),
                TaskItem(id: "3", title: "Release notes", due: now + 5 * 3600, hasTime: true),
                TaskItem(id: "4", title: "Water the plants"),
            ], completed: [])
        let timer = TimerFeature()
        timer.start(25 * 60, now: now - 12 * 60)
        defer { timer.cancel() }
        let prompter = PrompterFeature(defaults: UserDefaults(suiteName: "HP-\(UUID())")!)
        prompter.script =
            "Today I'll walk you through the five new looks, then we pick one together. Each one keeps the "
            + "notch's shape and its buttons where your hands expect them."
        let home = HomeView(
            media: media, calendar: calendar, tasks: tasks, timer: timer, prompter: prompter,
            usage: AnyView(UsageStandIn()), tabs: Set(FeatureID.allCases), open: { _ in })
        for (suffix, size) in Self.sizes {
            try render(home, name: "home\(suffix)", size: size)
        }
    }

    /// Nothing playing, no AI plans, no timer, nothing to do: the cards left take the room.
    @Test func fewerCards() throws {
        let tasks = TasksFeature(eventStore: EventStore(), defaults: UserDefaults(suiteName: "HT-\(UUID())")!)
        tasks.show(tasks: [], completed: [])
        let home = HomeView(
            media: MediaFeature(bundle: Bundle(for: HomeSnapshotMarker.self)),
            calendar: CalendarFeature(eventStore: EventStore(), defaults: UserDefaults(suiteName: "HC-\(UUID())")!),
            tasks: tasks, timer: TimerFeature(),
            prompter: PrompterFeature(defaults: UserDefaults(suiteName: "HP-\(UUID())")!), usage: nil,
            tabs: [.media, .tasks, .prompter], open: { _ in })
        try render(home, name: "home-fewer", size: Self.sizes[0].size)
    }

    @Test func whenTheNextEventStarts() {
        let now = Date.now
        let soon = DayEvent(id: "1", title: "Standup", start: now + 17 * 60 + 5, end: now + 3600)
        #expect(HomeView.when(soon, now: now) == "in 18 min")
        let started = DayEvent(id: "2", title: "Review", start: now - 60, end: now + 3600)
        #expect(HomeView.when(started, now: now) == "Now")
        let later = DayEvent(id: "3", title: "Gym", start: now + 2 * 3600, end: now + 3 * 3600)
        #expect(HomeView.when(later, now: now) == later.start.formatted(date: .omitted, time: .shortened))
    }

    /// The tab as the notch shows it, once its cards have risen into place (at once: no animation).
    private func render(_ view: some View, name: String, size: CGSize) throws {
        let root =
            view
            .frame(width: size.width, height: size.height)
            .padding(16)
            .background(theme.surface.color.color)
            .foregroundStyle(.themeInk)
            .environment(\.colorScheme, theme.appearance.colorScheme)
            .environment(\.theme, theme)
            .transaction {
                $0.animation = nil
                $0.disablesAnimations = true
            }
        let host = NSHostingView(rootView: root)
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

    /// A made-up album cover: a warm diagonal gradient, PNG-encoded like real artwork data.
    private static func sampleArtwork() -> Data? {
        let image = NSImage(size: CGSize(width: 600, height: 600), flipped: false) { rect in
            NSGradient(colors: [.systemOrange, .systemRed, .black])?.draw(in: rect, angle: -75)
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

/// Stands in for AI Usage's Home card, which this package's tests can't reach: a ring at 64%, the
/// provider, and its limit.
private struct UsageStandIn: View {
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(.themeInk.opacity(0.1), lineWidth: 4)
                Circle().trim(from: 0, to: 0.64).stroke(.themeAccent, lineWidth: 4).rotationEffect(.degrees(-90))
                Text("64%").themeFont(.numbers, size: 9, weight: .bold)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Claude").themeFont(.display, size: 13, weight: .semibold)
                Text("Session").themeFont(.body, size: 11).opacity(0.7)
            }
        }
    }
}

private final class HomeSnapshotMarker {}
