// SPDX-License-Identifier: MIT
import AppKit
import NotchTheme
import SwiftUI
import Testing

@testable import NotchFeatures

@MainActor
struct ShortcutsLogTests {
    private let defaults = UserDefaults(suiteName: "ShortcutsLogTests.\(UUID().uuidString)")!
    private let names = ["Lights off", "Log water", "Morning summary", "Resize images", "Start focus", "Text ETA"]

    @Test func favoritesStartAsTheFirstFourThenKeepTheUsersPicks() {
        let shortcuts = ShortcutsFeature(defaults: defaults)
        shortcuts.shortcuts = names
        #expect(shortcuts.favorites == Array(names.prefix(4)))
        shortcuts.unpin("Log water")
        shortcuts.pin("Start focus")
        shortcuts.pin("Text ETA")  // four already
        shortcuts.replace("Lights off", with: "Text ETA")
        let relaunched = ShortcutsFeature(defaults: defaults)
        relaunched.shortcuts = names
        #expect(relaunched.favorites == ["Text ETA", "Morning summary", "Resize images", "Start focus"])
        relaunched.hidden = ["Morning summary"]
        #expect(relaunched.favorites == ["Text ETA", "Resize images", "Start focus"])
    }

    @Test func theLogKeepsTheLastRunsNewestFirstWithWhatTheyDid() async {
        let echo = ShortcutsFeature(defaults: defaults, executable: "/bin/echo")
        echo.run("Hello")
        #expect(echo.log.first?.outcome == .running)
        #expect(await eventually { echo.log.first?.outcome == .done })
        #expect(echo.log.first?.output == "run Hello", "text the shortcut gives back is kept to copy")
        #expect(echo.log.first?.duration != nil)

        let failing = ShortcutsFeature(defaults: defaults, executable: "/usr/bin/false")
        for index in 0..<ShortcutsFeature.logLength + 2 { failing.run("Shortcut \(index)") }
        #expect(failing.log.count == ShortcutsFeature.logLength)
        #expect(failing.log.first?.name == "Shortcut 21")
        #expect(await eventually { failing.running.isEmpty })
        #expect(failing.log.allSatisfy { $0.outcome == .failed(nil) && $0.ended != nil })
        failing.clearLog()
        #expect(failing.log.isEmpty)
    }

    /// The tab with favorites and a log of every kind of run, then with nothing run yet (the full
    /// list). With SNAPSHOT_DIR set, writes shortcuts.png and shortcuts-list.png there, and their
    /// -smallest copies; AUDIT_THEME picks the theme, as in FeatureSnapshotTests.
    @Test func favoritesBesideTheLog() throws {
        let shortcuts = ShortcutsFeature(defaults: defaults)
        shortcuts.shortcuts = names + ["Translate clipboard"]
        shortcuts.status = .ready
        try render(shortcuts.view, name: "shortcuts-list")
        for name in shortcuts.favorites { shortcuts.unpin(name) }
        for name in ["Start focus", "Log water", "Morning summary", "Lights off"] { shortcuts.pin(name) }
        let now = Date.now
        shortcuts.log = [
            .init(name: "Resize images", started: now - 7),
            .init(
                name: "Translate clipboard", started: now - 660, ended: now - 658, outcome: .done,
                output: "Where is the station?", copied: true),
            .init(
                name: "Log water", started: now - 1500, ended: now - 1499, outcome: .done, output: "1.5 of 2 L today"),
            .init(name: "Text ETA", started: now - 1740, ended: now - 1738, outcome: .failed("needs Messages access")),
            .init(name: "Start focus", started: now - 2340, ended: now - 2331, outcome: .stopped),
            .init(name: "Morning summary", started: now - 4260, ended: now - 4257, outcome: .done),
        ]
        try render(shortcuts.view, name: "shortcuts")
    }

    // A copy of FeatureSnapshotTests' renderer, so this file stays the Shortcuts tab's own.

    private let size = CGSize(width: 428, height: 200)
    private static let smallest = CGSize(width: 350, height: 102)

    private func render(_ view: some View, name: String) throws {
        let theme = Themes.theme(ProcessInfo.processInfo.environment["AUDIT_THEME"] ?? "black")
        for (size, suffix) in [(size, ""), (Self.smallest, "-smallest")] {
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
