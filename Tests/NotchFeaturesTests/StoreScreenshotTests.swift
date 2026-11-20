// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import NotchTheme
import SwiftUI
import Testing

@testable import NotchFeatures

/// The App Store edition's tabs for the store and website screenshots, filled with made-up content
/// (a band, a week, a shelf of files that don't exist anywhere else). Each is drawn where the open
/// notch puts its tab, on nothing, at 2×, so StorePageShots in NotchSurfaceTests can lay it in the
/// real notch under its tab row. Off unless STORE_SHOTS_DIR is set; then each writes
/// `tabs/<shot>~<tab>~<theme>.png` there. The GitHub build's tabs are drawn the same way in
/// NotchUsageTests and NotchMixerTests. Draw them all first, then compose the pages:
///
///     export STORE_SHOTS_DIR=/tmp/shots
///     swift test --filter StoreTabShots
///     swift test --filter StorePageShots
@MainActor
@Suite(.enabled(if: shotsDirectory != nil))
struct StoreTabShots {
    /// The open notch in the screenshots: dragged a little larger than it opens at first, so every
    /// tab shows its roomy layout; a little shorter for the player, which needs less.
    static let notch = CGSize(width: 600, height: 360)
    static let player = CGSize(width: 600, height: 330)
    private let folder = FileManager.default.temporaryDirectory.appending(path: "StoreTabShots-\(UUID().uuidString)")

    // MARK: Shots

    /// Home as the App Store edition shows it, in Bento: no AI plans' card, so the network's speed
    /// fills its corner.
    @Test func home() async throws {
        let now = Date.now
        let home = HomeFeature(defaults: Self.defaults())
        home.add(.network)
        let calendar = CalendarFeature(eventStore: EventStore(), defaults: Self.defaults())
        calendar.show(events: [
            DayEvent(
                id: "1", title: "Design review", start: now + 18 * 60, end: now + 48 * 60,
                color: RGB(red: 0.35, green: 0.63, blue: 1), meeting: Self.call)
        ])
        let tasks = TasksFeature(eventStore: EventStore(), defaults: Self.defaults())
        tasks.show(
            tasks: [
                TaskItem(id: "1", title: "Send invoice", due: now - 1800, hasTime: true),
                TaskItem(id: "2", title: "Book flights", due: now + 1800, hasTime: true),
                TaskItem(id: "3", title: "Water plants"),
                TaskItem(id: "4", title: "Call dentist"),
            ], completed: [])
        let timer = TimerFeature()
        timer.start(25 * 60, now: now - 7 * 60)
        defer { timer.cancel() }
        let prompter = PrompterFeature(defaults: Self.defaults())
        prompter.script =
            "Thanks for coming, everyone. Three things shipped this week, and the one you asked for most "
            + "is first."
        let network = try sampleNetwork()
        defer { network.phase = .stopped }
        let view = HomeView(
            home: home, media: try playing(), calendar: calendar, tasks: tasks, timer: timer, prompter: prompter,
            notes: NotesFeature(directory: folder.appending(path: "HomeNotes"), defaults: Self.defaults()),
            clipboard: try copies(), shortcuts: ShortcutsFeature(defaults: Self.defaults()), network: network,
            usage: nil, tabs: Set(FeatureID.allCases).subtracting([.usage, .agents, .sound]), open: { _ in })
        try await Self.draw(view, shot: "home", tab: .home, theme: "bento")
    }

    /// The cover-led player, mid-song, with its waveform, in Black, where the cover's glow shows.
    @Test func music() async throws {
        try await Self.draw(try playing().view, shot: "music", tab: .media, theme: "black", notch: Self.player)
    }

    /// The same player in four looks, side by side in one screenshot.
    @Test(arguments: ["paper", "terminal", "brutal", "hifi"])
    func themes(theme: String) async throws {
        try await Self.draw(try playing().view, shot: "themes-\(theme)", tab: .media, theme: theme, notch: Self.player)
    }

    /// Next Monday's week strip and agenda, with that day's tasks beside it, in Paper.
    @Test func calendar() async throws {
        let calendar = CalendarFeature(eventStore: EventStore(), defaults: Self.defaults())
        let today = Calendar.current.startOfDay(for: .now)
        let monday = Calendar.current.nextDate(
            after: today, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)!
        func at(_ day: Date, _ hour: Int, _ minute: Int = 0) -> Date {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: monday)!.start
        func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: week)! }
        let blue = RGB(red: 0.31, green: 0.55, blue: 0.98)
        let green = RGB(red: 0.27, green: 0.72, blue: 0.47)
        let orange = RGB(red: 0.98, green: 0.58, blue: 0.24)
        let purple = RGB(red: 0.62, green: 0.45, blue: 0.95)
        calendar.select(monday)
        calendar.show(
            events: [
                DayEvent(id: "1", title: "Standup", start: at(monday, 9, 30), end: at(monday, 9, 45), color: blue),
                DayEvent(
                    id: "2", title: "Design review", start: at(monday, 11), end: at(monday, 12), color: blue,
                    meeting: Self.call),
                DayEvent(
                    id: "3", title: "Lunch with Maya", start: at(monday, 13), end: at(monday, 14), color: orange,
                    place: "Café Lune"),
                DayEvent(id: "4", title: "Dentist", start: at(monday, 16), end: at(monday, 16, 45), color: green),
                DayEvent(id: "5", title: "Yoga", start: at(monday, 18, 30), end: at(monday, 19, 30), color: purple),
                DayEvent(id: "6", title: "Sprint planning", start: at(day(2), 10), end: at(day(2), 11), color: blue),
                DayEvent(id: "7", title: "Book club", start: at(day(3), 19), end: at(day(3), 20), color: purple),
                DayEvent(id: "8", title: "Team lunch", start: at(day(5), 12), end: at(day(5), 13), color: orange),
            ],
            dueTasks: [
                TaskItem(id: "t1", title: "Send invoice", due: today - 86_400),
                TaskItem(id: "t2", title: "Dry cleaning", due: at(monday, 17), hasTime: true),
                TaskItem(id: "t3", title: "Order the cake", due: monday),
            ])
        try await Self.draw(calendar.view, shot: "calendar", tab: .calendar, theme: "paper")
    }

    /// The board, Today, Upcoming, and Done, in Island.
    @Test func tasks() async throws {
        let tasks = TasksFeature(eventStore: EventStore(), defaults: Self.defaults())
        let now = Date.now
        let today = Calendar.current.startOfDay(for: now)
        func day(_ offset: Int, hour: Int? = nil) -> Date {
            let date = Calendar.current.date(byAdding: .day, value: offset, to: today)!
            return hour.flatMap { Calendar.current.date(bySettingHour: $0, minute: 0, second: 0, of: date) } ?? date
        }
        tasks.show(
            tasks: [
                TaskItem(id: "1", title: "Send the invoice", due: day(-1)),
                TaskItem(id: "2", title: "Renew passport", due: today, priority: .high),
                TaskItem(id: "3", title: "Water the plants", due: today),
                TaskItem(id: "4", title: "Book flights", due: day(1, hour: 9), hasTime: true),
                TaskItem(id: "5", title: "Dry cleaning", due: day(3, hour: 17), hasTime: true),
                TaskItem(id: "6", title: "Order the cake", due: day(5)),
                TaskItem(id: "7", title: "Bake sourdough"),
            ],
            completed: [
                TaskItem(id: "8", title: "Pay the rent", completed: now - 3 * 3600),
                TaskItem(id: "9", title: "Reply to the landlord", completed: now - 26 * 3600),
            ])
        try await Self.draw(tasks.view, shot: "tasks", tab: .tasks, theme: "island")
    }

    /// The list beside the open note, its Markdown shown as it reads, in Cozy.
    @Test func notes() async throws {
        let notes = NotesFeature(directory: folder.appending(path: "Notes"), defaults: Self.defaults())
        let now = Date.now
        let trip = Note(
            id: UUID(),
            text: """
                # Weekend in Lisbon
                - [x] Book the flat in Alfama
                - [x] Train from the airport
                - [ ] Tram 28 before nine
                - [ ] Pastéis de nata in Belém
                - [ ] **Sunset** at the Graça lookout
                """, modified: now - 4 * 60, color: .orange)
        notes.phase = .foreground  // loads the empty folder first, so these stay
        notes.show(notes: [
            trip,
            Note(id: UUID(), text: "Groceries\nOat milk, lemons, coffee beans", modified: now - 3 * 3600),
            Note(
                id: UUID(), text: "Shop window ideas\nPaper lanterns, a reading nook", modified: now - 26 * 3600,
                color: .mint),
            Note(id: UUID(), text: "Reading list\nThree novels for the flight", modified: now - 4 * 86_400),
        ])
        notes.selection = trip.id
        try await Self.draw(notes.view, shot: "notes", tab: .notes, theme: "cozy")
        notes.phase = .stopped
    }

    /// Copies as cards, words, a photo, a color, a link, and a command, in Brutal.
    @Test func clipboard() async throws {
        try await Self.draw(try copies().view, shot: "clipboard", tab: .clipboard, theme: "brutal")
    }

    /// The shelf's tray, files waiting to be dropped somewhere else, two picked, in Aurora.
    @Test func shelf() async throws {
        let directory = folder.appending(path: "Shelf")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let shelf = ShelfFeature(
            storeURL: directory.appending(path: "shelf.json"),
            pasteboard: NSPasteboard(name: .init("StoreShelf.\(UUID())")))
        shelf.add(try Self.files(in: directory))
        shelf.phase = .foreground
        shelf.select(shelf.items[0], adding: false)
        shelf.select(shelf.items[2], adding: true)
        try await Self.draw(shelf.view, shot: "shelf", tab: .shelf, theme: "aurora", wait: .seconds(2))
    }

    /// A focus timer under way on its dial, in Matrix.
    @Test func timer() async throws {
        let timer = TimerFeature()
        timer.start(25 * 60, now: .now - 7 * 60 - 18)
        defer { timer.cancel() }
        try await Self.draw(timer.view, shot: "timer", tab: .timer, theme: "matrix")
    }

    /// A script part-read, the next word lit, in Voice mode, in Terminal. It's started in Scroll mode
    /// and paused, so the microphone is never asked for.
    @Test func prompter() async throws {
        let prompter = PrompterFeature(defaults: Self.defaults())
        prompter.phase = .foreground
        prompter.script =
            "Good morning, everyone. Thanks for joining so early. This quarter we shipped the three things you "
            + "asked for most, and I want to show you each one before we take questions. First, the new home "
            + "screen: everything you need at a glance."
        prompter.mode = .scroll
        prompter.start()
        prompter.pause()
        prompter.jump(to: 5)
        prompter.mode = .voice
        try await Self.draw(prompter.view, shot: "prompter", tab: .prompter, theme: "terminal")
        prompter.phase = .stopped
    }

    // MARK: Made-up content

    private static func defaults() -> UserDefaults { UserDefaults(suiteName: "StoreTabShots-\(UUID())")! }

    /// A made-up meeting's video call, which gets a Join button.
    private static let call = MeetingLink(URL(string: "https://zoom.us/j/5550142")!)

    /// "Slow Light" by Juniper Coast, a band made up for these, two minutes into the song.
    private func playing() throws -> MediaFeature {
        let media = MediaFeature(bundle: Bundle(for: StoreShotsMarker.self), defaults: Self.defaults())
        media.receive(
            NowPlaying(
                title: "Slow Light", artist: "Juniper Coast", album: "Low Tide", isPlaying: true, duration: 231,
                elapsed: 128, timestamp: .now, artwork: Self.cover(), appBundleID: nil, shuffle: false,
                repeatMode: .all))
        #expect(media.artwork != nil)
        return media
    }

    /// Five copies on a private pasteboard, never the user's own: a note, a link, a photo, a color,
    /// and a command, each from the app in front at the time.
    private func copies() throws -> ClipboardFeature {
        let directory = folder.appending(path: "Clipboard-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pasteboard = NSPasteboard(name: .init("StoreClipboard.\(UUID().uuidString)"))
        let app = AppInFront()
        let clipboard = ClipboardFeature(
            pasteboard: pasteboard, defaults: Self.defaults(), storeURL: directory.appending(path: "clipboard.json"),
            imagesURL: directory.appending(path: "Images"), frontmostApp: { (nil, app.name) })
        clipboard.phase = .foreground
        clipboard.startRecording()
        let copies: [(String, Any)] = [  // oldest first
            ("Terminal", "git switch -c polish-the-shelf"),
            ("Safari", "https://example.com/lisbon/alfama-walking-tour"),
            ("Mail", "#E8573F"),
            ("Preview", NSImage(data: Self.photo(Self.coast, size: CGSize(width: 720, height: 300))!)!),
            ("Notes", "Meet at six by the north door, then dinner at Nori"),
        ]
        for (name, copy) in copies {
            app.name = name
            pasteboard.clearContents()
            if let text = copy as? String {
                pasteboard.setString(text, forType: .string)
            } else if let image = copy as? NSImage {
                pasteboard.writeObjects([image])
            }
            clipboard.check()
        }
        let note = try #require(clipboard.items.first { $0.text.hasPrefix("Meet") })
        clipboard.toggleFavorite(note)
        clipboard.setColor(ClipColor.sand.rawValue, for: note)
        return clipboard
    }

    /// 2.4 MB/s down and 180 KB/s up, after a day of nothing else.
    private func sampleNetwork() throws -> NetworkFeature {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var counters = ["en0": Traffic(down: 5_000_000_000, up: 900_000_000)]
        let network = NetworkFeature(
            defaults: Self.defaults(), storeURL: folder.appending(path: "network-\(UUID()).sqlite"), netSpeedURL: nil,
            readCounters: { counters })
        network.closedNotch = .off
        network.phase = .foreground
        counters["en0"] = Traffic(down: 5_002_400_000, up: 900_180_000)
        network.receive(counters, at: .now + 1)
        network.phase = .background
        return network
    }

    /// Files Quick Look draws thumbnails of: photos, a PDF, a Markdown file; and a folder.
    private static func files(in folder: URL) throws -> [URL] {
        func write(_ name: String, _ data: Data?) throws -> URL {
            let url = folder.appending(path: name)
            try (data ?? Data(name.utf8)).write(to: url)
            return url
        }
        let assets = folder.appending(path: "Brand assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        return [
            try write("IMG_2041.jpg", photo(dusk, size: CGSize(width: 900, height: 600), type: .jpeg)),
            try write("Invoice-November.pdf", invoice()),
            try write("Moodboard.png", photo(meadow, size: CGSize(width: 900, height: 600))),
            try write(
                "Trip plan.md",
                Data("# Lisbon\n\n- Alfama walking tour\n- Tram 28\n- Belém on Sunday\n- Sintra day trip\n".utf8)),
            try write("IMG_2077.jpg", photo(coast, size: CGSize(width: 900, height: 600), type: .jpeg)),
            assets,
        ]
    }

    /// A made-up photo's sky (from the horizon up), its sun, and its hills (back to front).
    struct Scene: Sendable {
        var sky: [NSColor]
        var sun: NSColor
        var hills: [NSColor]
    }

    nonisolated static let dusk = Scene(
        sky: [Self.rgb(0xFFB46B), Self.rgb(0xE8577A), Self.rgb(0x4B2C73)], sun: Self.rgb(0xFFE2A8),
        hills: [Self.rgb(0x8A3E6B), Self.rgb(0x5B2A5E), Self.rgb(0x2E1A3F)])
    nonisolated static let meadow = Scene(
        sky: [Self.rgb(0xF6E7B8), Self.rgb(0x9FD3E6), Self.rgb(0x5AA6D6)], sun: Self.rgb(0xFFF6D8),
        hills: [Self.rgb(0x9CC97A), Self.rgb(0x5E9E5A), Self.rgb(0x2F6B45)])
    nonisolated static let coast = Scene(
        sky: [Self.rgb(0xFBD3B0), Self.rgb(0xA9C6E8), Self.rgb(0x6B8FCB)], sun: Self.rgb(0xFFFFFF),
        hills: [Self.rgb(0x7FB3C9), Self.rgb(0x3F7FA6), Self.rgb(0x1F4E79)])

    nonisolated private static func rgb(_ hex: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// A made-up landscape: the sky's gradient from the horizon up, the sun low in it, and three
    /// ranges of rolling hills in front, encoded as `type`.
    nonisolated static func photo(_ scene: Scene, size: CGSize, type: NSBitmapImageRep.FileType = .png) -> Data? {
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: scene.sky)?.draw(in: rect, angle: 90)
            scene.sun.setFill()
            let sun = rect.height * 0.16
            NSBezierPath(ovalIn: CGRect(x: rect.width * 0.62, y: rect.height * 0.42, width: sun, height: sun)).fill()
            for (index, color) in scene.hills.enumerated() {
                let base = rect.height * (0.42 - 0.12 * CGFloat(index))
                let path = NSBezierPath()
                path.move(to: .zero)
                for x in stride(from: 0, through: rect.width, by: 8) {
                    let wave = sin(x / rect.width * .pi * (1.6 + CGFloat(index)) + CGFloat(index) * 1.7)
                    path.line(to: CGPoint(x: x, y: base + wave * rect.height * 0.07))
                }
                path.line(to: CGPoint(x: rect.width, y: 0))
                path.close()
                color.setFill()
                path.fill()
            }
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: type, properties: [:])
    }

    /// Low Tide's cover: the sun setting into a violet sea, its light in stripes on the water, and the
    /// title along the top.
    nonisolated static func cover() -> Data? {
        let image = NSImage(size: CGSize(width: 600, height: 600), flipped: false) { rect in
            let horizon = rect.height * 0.4
            let sky = CGRect(x: 0, y: horizon, width: rect.width, height: rect.height - horizon)
            NSGradient(colors: [rgb(0xFFB46B), rgb(0xF0687A), rgb(0x5A2F7D)])?.draw(in: sky, angle: 90)
            rgb(0xFFE2A8).setFill()
            NSBezierPath(ovalIn: CGRect(x: 205, y: horizon - 70, width: 190, height: 190)).fill()
            let sea = CGRect(x: 0, y: 0, width: rect.width, height: horizon)
            NSGradient(colors: [rgb(0x1C1438), rgb(0x4E3483)])?.draw(in: sea, angle: 90)
            rgb(0xFFC98B).withAlphaComponent(0.85).setFill()
            for row in 0..<9 {
                let width = 180 - CGFloat(row) * 17
                let stripe = CGRect(x: 300 - width / 2, y: horizon - 14 - CGFloat(row) * 25, width: width, height: 7)
                NSBezierPath(roundedRect: stripe, xRadius: 3.5, yRadius: 3.5).fill()
            }
            let title: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 40, weight: .black), .foregroundColor: rgb(0xFFF4E6), .kern: 6,
            ]
            ("LOW TIDE" as NSString).draw(at: CGPoint(x: 44, y: 516), withAttributes: title)
            let band: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: rgb(0xFFF4E6), .kern: 4,
            ]
            ("JUNIPER COAST" as NSString).draw(at: CGPoint(x: 46, y: 484), withAttributes: band)
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// A one-page invoice from a made-up studio: a colored band and a few lines.
    nonisolated private static func invoice() -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data),
            let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return Data() }
        context.beginPDFPage(nil)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        rgb(0xE8573F).setFill()
        NSRect(x: 72, y: 690, width: 220, height: 40).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22)]
        for (index, line) in ["Studio Fern", "Invoice 0142 · November", "Illustration · 12 h", "Total due: $1,840"]
            .enumerated()
        {
            (line as NSString).draw(at: CGPoint(x: 72, y: 620 - index * 48), withAttributes: attributes)
        }
        NSGraphicsContext.current = nil
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    // MARK: Drawing

    /// Draws `view` as the open notch lays out a tab in `theme`: the notch's size, with the tab in
    /// its room under the header, inside the theme's margins, and nothing around it, so a glow that
    /// reaches past the tab's edges is kept. `wait` lets what the tab does on appearing finish (Quick
    /// Look's thumbnails, times rolling into place); without animation it happens at once.
    static func draw(
        _ view: some View, shot: String, tab: FeatureID, theme id: String, notch: CGSize = StoreTabShots.notch,
        wait: Duration = .seconds(1)
    ) async throws {
        guard let directory = shotsDirectory else { return }
        let theme = Themes.theme(id)
        let side = theme.radii.notchTop + 22
        let top: CGFloat = 32 + 10 + 26 + 8  // the camera housing, the gap, the tab row, and the gap under it
        let room = CGSize(width: notch.width - 2 * side, height: notch.height - top - 22)
        let root = view.frame(width: room.width, height: room.height)
            .padding(EdgeInsets(top: top, leading: side, bottom: 22, trailing: side))
            .foregroundStyle(.themeInk)
            .environment(\.colorScheme, theme.appearance.colorScheme)
            .environment(\.theme, theme)
            .transaction {
                $0.animation = nil
                $0.disablesAnimations = true  // times that tick mid-render land at once, not mid-roll
            }
        let host = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: notch), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // An await, for work that needs the main actor (thumbnails); then the run loop, which the
        // hosting view updates on (what changed on appearing).
        try await Task.sleep(for: wait)
        runLoop(for: 0.3)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let tabs = URL(filePath: directory).appending(path: "tabs")
        try FileManager.default.createDirectory(at: tabs, withIntermediateDirectories: true)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: tabs.appending(path: "\(shot)~\(tab.rawValue)~\(id).png"))
    }

    /// Runs the main run loop a while; out of an async context, where Swift won't call it directly.
    private static func runLoop(for seconds: TimeInterval) {
        RunLoop.main.run(until: .now + seconds)
    }
}

/// Where the shots go; nil skips them.
private let shotsDirectory = ProcessInfo.processInfo.environment["STORE_SHOTS_DIR"]

/// The app a copy came from, changed between copies.
private final class AppInFront {
    var name = ""
}

private final class StoreShotsMarker {}
