// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import NotchTheme
import SwiftUI
import Testing

@testable import NotchSurface

/// Where the screenshots are drawn; nil skips them.
private let shotsDirectory = ProcessInfo.processInfo.environment["STORE_SHOTS_DIR"]

/// The App Store and website screenshots, from the app's own views: each tab the StoreTabShots
/// drew (NotchFeaturesTests, NotchUsageTests, NotchMixerTests) set in the real open notch under its
/// tab row, on a made-up desktop, beside the copy. Off unless STORE_SHOTS_DIR is set; run
/// `swift test --filter StoreTabShots` first, which leaves the tabs in `tabs/` there, then
/// `swift test --filter StorePageShots`, which writes, in that folder:
///
/// - `app-store/NN-<page>.png`: 2560×1600, sRGB, no alpha, the App Store edition's tabs only;
/// - `web/<page>.png`: the same pages at 1440×900, and the GitHub build's three extra ones;
/// - `web/panel-<page>.png`: each page's notch on its desktop alone, at 1440×900.
///
/// STORE_SHOTS_APP_STORE_DIR and STORE_SHOTS_WEB_DIR send the two sets somewhere else instead, such
/// as the launch kit's folders.
@MainActor
@Suite(.enabled(if: shotsDirectory != nil))
struct StorePageShots {
    /// A page of the set. `store` numbers the App Store's pages; the rest are the GitHub build's.
    struct Page {
        var name: String
        var store: Int?
        var eyebrow: String
        var headline: String
        var subtitle: String
        /// The chip lit, a tab's name.
        var chip: String?
        /// The tabs drawn for it, by shot name: one, or several side by side.
        var shots: [String]
    }

    static let pages = [
        Page(
            name: "home", store: 1, eyebrow: "New in 2.0", headline: "Your whole day\nin the notch.",
            subtitle: "Hover the notch for Home: the song that's on, your next meeting, today's tasks, "
                + "and a timer, each a click from its tab.", chip: "Home", shots: ["home"]),
        Page(
            name: "music", store: 2, eyebrow: "Now playing", headline: "The cover\ncomes first.",
            subtitle: "Big artwork, a seek bar that ripples while the song plays, and a waveform "
                + "moving along under it. Swipe with two fingers to skip.", chip: "Music", shots: ["music"]),
        Page(
            name: "themes", store: 3, eyebrow: "Themes", headline: "Dress up\nyour notch.",
            subtitle: "Pick a look and every tab follows it: type, icons, controls, even the player. "
                + "Here's one song in Paper, Terminal, Brutal and Hi-Fi.", chip: nil,
            shots: ["themes-paper", "themes-terminal", "themes-brutal", "themes-hifi"]),
        Page(
            name: "calendar", store: 4, eyebrow: "Calendar", headline: "Your week,\none hover away.",
            subtitle: "A strip of the week, the day's agenda, and the tasks due beside it. Add an "
                + "event by typing it the way you'd say it.", chip: "Calendar", shots: ["calendar"]),
        Page(
            name: "tasks", store: 5, eyebrow: "Tasks", headline: "Today, next,\nand done.",
            subtitle: "Your reminders on a board of three columns. Drag a card to another day, or "
                + "drop it on Done when it's finished.", chip: "Tasks", shots: ["tasks"]),
        Page(
            name: "notes", store: 6, eyebrow: "Notes", headline: "Jot it down\nbefore it's gone.",
            subtitle: "Notes kept as plain Markdown files on your Mac, a list beside the page, and "
                + "checklists you tick right there.", chip: "Notes", shots: ["notes"]),
        Page(
            name: "clipboard", store: 7, eyebrow: "Clipboard", headline: "Everything\nyou copied.",
            subtitle: "Text, links, images and colors, kept on your Mac and searchable. Star the "
                + "ones you reuse and give them a color.", chip: "Clipboard", shots: ["clipboard"]),
        Page(
            name: "shelf", store: 8, eyebrow: "Shelf", headline: "Park your files\nup top.",
            subtitle: "Drop files on the notch to keep them close, then drag them out where they "
                + "go, AirDrop them, or copy them.", chip: "Shelf", shots: ["shelf"]),
        Page(
            name: "timer", store: 9, eyebrow: "Timers & stopwatch", headline: "Set a timer\nin one tap.",
            subtitle: "Pick a length on the dial or type your own. There's a stopwatch with laps, and "
                + "Keep Awake for when your Mac has to stay up.", chip: "Timer", shots: ["timer"]),
        Page(
            name: "prompter", store: 10, eyebrow: "Prompter", headline: "Your script,\nby the camera.",
            subtitle: "A teleprompter under the camera that follows your voice as you read, and "
                + "stays out of screen sharing while it's up.", chip: "Prompter", shots: ["prompter"]),
        Page(
            name: "ai-usage", eyebrow: "AI Usage · GitHub edition", headline: "Know your\nAI limits.",
            subtitle: "Session and weekly limits for Claude, Codex, Cursor, Copilot and more, each with "
                + "the time left until it resets.", chip: "AI Usage", shots: ["ai-usage"]),
        Page(
            name: "agents", eyebrow: "Agents · GitHub edition", headline: "Know when agents\nneed you.",
            subtitle: "Claude Code and Codex sessions in one feed: what started, what finished, and "
                + "what's waiting on you.", chip: "Agents", shots: ["agents"]),
        Page(
            name: "sound", eyebrow: "Sound · GitHub edition", headline: "A volume\nfor every app.",
            subtitle: "Give each app its own fader, mute the noisy one, and switch where the sound "
                + "plays, without opening Settings.", chip: "Sound", shots: ["sound"]),
    ]

    /// The App Store edition's tabs, as chips; the GitHub build adds its three.
    static let storeChips = [
        "Home", "Music", "Shelf", "Clipboard", "Calendar", "Tasks", "Notes", "Shortcuts", "Timer", "Network",
        "Mirror", "Prompter",
    ]
    static let gitHubChips = storeChips + ["Sound", "AI Usage", "Agents"]

    @Test func everyPage() throws {
        Themes.registerFonts()
        let directory = URL(filePath: try #require(shotsDirectory))
        let tabs = try Self.tabs(in: directory.appending(path: "tabs"))
        func folder(_ variable: String, or name: String) -> URL {
            ProcessInfo.processInfo.environment[variable].map { URL(filePath: $0) } ?? directory.appending(path: name)
        }
        let store = folder("STORE_SHOTS_APP_STORE_DIR", or: "app-store")
        let web = folder("STORE_SHOTS_WEB_DIR", or: "web")
        for set in [store, web] {
            try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        }
        for page in Self.pages {
            let notches = try page.shots.map { shot in
                let tab = try #require(tabs[shot], "no tab drawn for \(shot): run StoreTabShots first")
                return (name: Themes.theme(tab.theme).name, image: try notch(tab, gitHub: page.store == nil))
            }
            let stage: AnyView =
                notches.count == 1
                ? AnyView(Desktop(notch: notches[0].image, screen: Desktop.screen))
                : AnyView(ThemeGrid(notches: notches))
            let chips = page.store == nil ? Self.gitHubChips : Self.storeChips
            let screenshot = Screenshot(page: page, chips: chips, stage: stage)
            if let number = page.store {
                let name = String(format: "%02d-%@.png", number, page.name)
                try Self.write(screenshot, size: CGSize(width: 2560, height: 1600), to: store.appending(path: name))
            }
            try Self.write(screenshot, size: Screenshot.canvas, to: web.appending(path: "\(page.name).png"))
            try Self.write(
                Bare(stage: stage, wide: notches.count == 1), size: Screenshot.canvas,
                to: web.appending(path: "panel-\(page.name).png"))
        }
    }

    // MARK: The notch

    /// A tab StoreTabShots drew: the open notch's size, the tab where it goes, and the rest clear.
    struct Tab {
        var feature: FeatureID
        var theme: String
        var image: NSImage
    }

    /// The drawn tabs by shot, from their file names (`<shot>~<tab>~<theme>.png`); the newest, when
    /// an earlier run left the shot in another theme.
    static func tabs(in folder: URL) throws -> [String: Tab] {
        var tabs: [String: (tab: Tab, drawn: Date)] = [:]
        let key = URLResourceKey.contentModificationDateKey
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [key])
        where file.pathExtension == "png" {
            let parts = file.deletingPathExtension().lastPathComponent.split(separator: "~").map(String.init)
            let drawn = try file.resourceValues(forKeys: [key]).contentModificationDate ?? .distantPast
            guard parts.count == 3, let feature = FeatureID(rawValue: parts[1]),
                drawn > tabs[parts[0]]?.drawn ?? .distantPast,
                let rep = NSBitmapImageRep(data: try Data(contentsOf: file))
            else { continue }
            let image = NSImage(size: CGSize(width: rep.pixelsWide / 2, height: rep.pixelsHigh / 2))
            image.addRepresentation(rep)
            tabs[parts[0]] = (Tab(feature: feature, theme: parts[2], image: image), drawn)
        }
        return tabs.mapValues(\.tab)
    }

    /// The open notch on `tab` in its theme, as the app draws it: the tab row of the App Store
    /// edition (or every tab, for the GitHub build's pages) with Home and Prompter turned on, and
    /// the tab under it.
    private func notch(_ tab: Tab, gitHub: Bool) throws -> NSImage {
        let preferences = NotchPreferences(
            defaults: UserDefaults(suiteName: "StoreScreenshots.\(UUID().uuidString)")!,
            unavailable: gitHub ? [] : [.usage, .agents, .sound])
        preferences.setEnabled(.home, true)
        preferences.setEnabled(.prompter, true)
        preferences.themeID = tab.theme
        preferences.resizeExpanded(to: tab.image.size)
        let engine = NotchEngine()
        for event in [NotchEvent.show, .selectTab(tab.feature)] { engine.send(event) }
        let theme = Themes.theme(tab.theme)
        let side = theme.radii.notchTop + 22
        let top: CGFloat = 32 + 10 + 26 + 8  // as StoreTabShots drew it, under the tab row
        let content = NotchContent(
            tab: { _ in
                AnyView(
                    Color.clear.overlay(alignment: .topLeading) {
                        Image(nsImage: tab.image).offset(x: -side, y: -top)
                    })
            },
            dropFiles: { _ in false }, openSettings: {})
        let size = tab.image.size
        let view = NotchView(engine: engine, metrics: Self.metrics, preferences: preferences, content: content)
            .frame(width: size.width, height: size.height)
            .transaction { $0.animation = nil }
        let rep = try #require(NotchSnapshotTests.render(view, size: size, name: "store-notch", settle: true))
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    /// A 14" MacBook Pro's display and notch.
    private static let metrics = NotchMetrics(
        screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
        left: CGRect(x: 0, y: 950, width: 662, height: 32), right: CGRect(x: 850, y: 950, width: 662, height: 32))

    // MARK: Writing

    /// Draws `view` on the 1440×900 canvas, scaled to `size` in pixels, without alpha, as an sRGB PNG.
    static func write(_ view: some View, size: CGSize, to url: URL) throws {
        let renderer = ImageRenderer(
            content: view.frame(width: Screenshot.canvas.width, height: Screenshot.canvas.height))
        renderer.scale = size.width / Screenshot.canvas.width
        renderer.isOpaque = true
        let image = try #require(renderer.cgImage)
        let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        let flat = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, flat, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}

// MARK: - The page

/// The colors of the launch pages: cream paper, warm ink, the mascot's red.
private enum Palette {
    static let cream = Color(red: 0xFA / 255, green: 0xF1 / 255, blue: 0xE4 / 255)
    static let ink = Color(red: 0x1B / 255, green: 0x16 / 255, blue: 0x13 / 255)
    static let quiet = Color(red: 0x6F / 255, green: 0x68 / 255, blue: 0x5C / 255)
    static let rust = Color(red: 0xB4 / 255, green: 0x53 / 255, blue: 0x2A / 255)
    static let red = Color(red: 0xE8 / 255, green: 0x57 / 255, blue: 0x3F / 255)
    static let chip = Color(red: 0xFF / 255, green: 0xFC / 255, blue: 0xF6 / 255)
    static let chipLine = Color(red: 0xE6 / 255, green: 0xD7 / 255, blue: 0xC2 / 255)
    static let lit = Color(red: 0xEF / 255, green: 0xA0 / 255, blue: 0x6C / 255)
}

/// The bundled faces: Bricolage Grotesque for the headline and the name, Inter for the rest, and
/// IBM Plex Mono for the eyebrow.
private enum Face {
    static func display(_ size: CGFloat) -> Font { Themes.theme("bento").font(.display, size: size, weight: .heavy) }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Themes.theme("bento").font(.body, size: size, weight: weight)
    }
    static func mono(_ size: CGFloat) -> Font { Themes.theme("terminal").font(.mono, size: size, weight: .semibold) }
}

/// One screenshot: the copy on the left, as the 1.4 pages had it, and the notch on its desktop on
/// the right.
private struct Screenshot: View {
    static let canvas = CGSize(width: 1440, height: 900)
    /// The copy's column, from the left edge.
    static let column: (start: CGFloat, width: CGFloat) = (96, 470)
    /// Between the stage and the right edge.
    static let margin: CGFloat = 40
    let page: StorePageShots.Page
    let chips: [String]
    let stage: AnyView

    var body: some View {
        ZStack(alignment: .leading) {
            Palette.cream
            stage.fixedSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, Self.margin)
            copy.frame(width: Self.column.width, alignment: .leading).padding(.leading, Self.column.start)
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height)
        .clipped()
    }

    /// The headline at the largest size whose every line fits the column.
    private var headline: some View {
        ViewThatFits(in: .horizontal) {
            headline(72)
            headline(66)
            headline(60)
            headline(54)
        }
    }

    private func headline(_ size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: -size * 0.2) {
            ForEach(page.headline.split(separator: "\n").map(String.init), id: \.self) { line in
                Text(line).font(Face.display(size)).tracking(-size * 0.036).fixedSize()
            }
        }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Image(nsImage: Self.icon).resizable().frame(width: 64, height: 64)
                (Text("I") + Text("Love").foregroundStyle(Palette.red) + Text("Notch"))
                    .font(Face.display(40)).tracking(-1)
            }
            .padding(.leading, -6)  // the icon's own margin
            Text(page.eyebrow.uppercased())
                .font(Face.mono(15)).tracking(2.5).foregroundStyle(Palette.rust)
                .padding(.top, 34)
            headline
                .padding(.top, 12)
            Text(page.subtitle)
                .font(Face.body(21)).foregroundStyle(Palette.quiet).lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)
            Flow(spacing: 9) {
                ForEach(chips, id: \.self) { chip in
                    let lit = chip == page.chip
                    Text(chip)
                        .font(Face.body(16, .semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(lit ? Palette.lit : Palette.chip, in: Capsule())
                        .overlay(Capsule().strokeBorder(lit ? Palette.lit : Palette.chipLine, lineWidth: 1.5))
                }
            }
            .padding(.top, 30)
        }
        .foregroundStyle(Palette.ink)
    }

    /// The app's icon, from its asset catalog.
    static let icon: NSImage = {
        let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = repository.appending(path: "App/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
        return NSImage(contentsOf: file) ?? NSImage()
    }()
}

/// A page's notch on its desktop alone, larger, for the website's feature pages.
private struct Bare: View {
    let stage: AnyView
    let wide: Bool

    var body: some View {
        let scale: CGFloat = wide ? 1.3 : 1.36
        ZStack {
            Palette.cream
            stage.scaleEffect(scale)
        }
        .frame(width: Screenshot.canvas.width, height: Screenshot.canvas.height)
        .clipped()
    }
}

/// Chips in rows, as many to a row as fit.
private struct Flow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        rows(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, origin) in zip(subviews, rows(subviews, width: bounds.width).origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var row: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += row + spacing
                row = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return (origins, CGSize(width: widest, height: y + row))
    }
}

// MARK: - The desktop

/// A MacBook's display in a light bezel: a made-up wallpaper, the menu bar, and the open notch at the
/// top, flush with the edge as it sits on the real one.
private struct Desktop: View {
    /// The display the pages show, around a 600 pt wide notch.
    static let screen = CGSize(width: 780, height: 520)
    static let bezel: CGFloat = 8

    let notch: NSImage
    let screen: CGSize

    var body: some View {
        ZStack(alignment: .top) {
            Wallpaper()
            // Only where there's room beside the notch for the menus and the clock to show whole.
            if screen.width - notch.size.width >= 160 { MenuBar() }
            Image(nsImage: notch)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        }
        .frame(width: screen.width, height: screen.height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(Self.bezel)
        .background {
            RoundedRectangle(cornerRadius: 18 + Self.bezel, style: .continuous)
                .fill(.white)
                .shadow(color: Color(red: 0.42, green: 0.27, blue: 0.15).opacity(0.22), radius: 34, y: 20)
        }
    }
}

/// Dusk in soft light: peach at the top, where the notch is, to violet below.
private struct Wallpaper: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    colors: [Self.hex(0xFFC8A0), Self.hex(0xF3968F), Self.hex(0x9479C6)], startPoint: .top,
                    endPoint: .bottom)
                Ellipse().fill(Self.hex(0xFFDB8F)).frame(width: size.width * 0.7, height: size.height * 0.7)
                    .blur(radius: 90).offset(x: -size.width * 0.32, y: -size.height * 0.3)
                Ellipse().fill(Self.hex(0xFF7C74)).frame(width: size.width * 0.6, height: size.height * 0.6)
                    .blur(radius: 100).offset(x: size.width * 0.36, y: -size.height * 0.05)
                Ellipse().fill(Self.hex(0x5E55B8)).frame(width: size.width * 0.9, height: size.height * 0.6)
                    .blur(radius: 110).offset(x: -size.width * 0.1, y: size.height * 0.48)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    static func hex(_ value: Int) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

/// The menu bar over the wallpaper: Finder's menus on the left and the status items and clock on the
/// right, where the notch leaves room for them.
private struct MenuBar: View {
    var body: some View {
        HStack(spacing: 17) {
            Text("Finder").fontWeight(.bold)
            ForEach(["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) { Text($0) }
            Spacer(minLength: 0)
            ForEach(["switch.2", "magnifyingglass", "battery.75percent", "wifi"], id: \.self) {
                Image(systemName: $0)
            }
            Text(Self.clock)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Palette.ink.opacity(0.85))  // dark, as macOS draws it on a light wallpaper
        .padding(.horizontal, 16)
        .frame(height: 30)
    }

    /// The time the pages are drawn: all of the clock that fits beside the open notch.
    private static var clock: String { Date.now.formatted(date: .omitted, time: .shortened) }
}

/// The themes page's stage: one tab in four looks, each on a smaller display with its name under it.
private struct ThemeGrid: View {
    let notches: [(name: String, image: NSImage)]
    private static let screen = CGSize(width: 680, height: 400)
    private static let scale: CGFloat = 0.55

    var body: some View {
        Grid(horizontalSpacing: 26, verticalSpacing: 22) {
            ForEach(Array(stride(from: 0, to: notches.count, by: 2)), id: \.self) { start in
                GridRow {
                    ForEach(start..<min(start + 2, notches.count), id: \.self) { index in
                        VStack(spacing: 12) {
                            Desktop(notch: notches[index].image, screen: Self.screen)
                                .scaleEffect(Self.scale)
                                .frame(
                                    width: (Self.screen.width + 2 * Desktop.bezel) * Self.scale,
                                    height: (Self.screen.height + 2 * Desktop.bezel) * Self.scale)
                            Text(notches[index].name)
                                .font(Face.body(17, .semibold))
                                .foregroundStyle(Palette.ink)
                        }
                    }
                }
            }
        }
    }
}
