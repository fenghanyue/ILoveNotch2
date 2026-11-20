// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import NotchTheme
import SwiftUI
import Testing

@testable import NotchUsage

/// Where the shots go; nil skips them.
private let shotsDirectory = ProcessInfo.processInfo.environment["STORE_SHOTS_DIR"]

/// The GitHub build's AI Usage and Agents tabs for the website's screenshots, with made-up plans
/// and projects, drawn as NotchFeaturesTests' StoreTabShots draws the App Store edition's tabs
/// (which explains the folder and the order to run them in).
@MainActor
@Suite(.enabled(if: shotsDirectory != nil))
struct StoreTabShots {
    private static let notch = CGSize(width: 600, height: 360)
    private let root = FileManager.default.temporaryDirectory.appending(path: "StoreTabShots-\(UUID().uuidString)")

    /// Four plans, each with its session and weekly limits and when they reset.
    @Test func aiUsage() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "StoreTabShots-\(UUID())")!
        let cache = root.appending(path: "usage.json")
        let plans = [
            Self.plan("claude", "Claude", plan: "Max", session: 38, weekly: 61, resets: 2 * 3600 + 780),
            Self.plan("codex", "Codex", plan: "Pro", session: 72, weekly: 44, resets: 3 * 3600 + 1500),
            Self.plan("cursor", "Cursor", plan: "Pro", session: 91, weekly: 83, resets: 41 * 60),
            Self.plan("copilot", "Copilot", plan: "Pro", session: 17, weekly: 9, resets: 5 * 86_400),
        ]
        try JSONEncoder().encode(Dictionary(uniqueKeysWithValues: plans.map { ($0.providerID, $0) })).write(to: cache)
        defaults.set(plans.map(\.providerID), forKey: "usage.enabledProviders")
        let runtimes = plans.map { FakeRuntime(id: $0.providerID, name: $0.displayName, used: 0) }
        let usage = UsageFeature(defaults: defaults, cacheURL: cache, runtimes: { runtimes })
        // The rings fill from empty when they appear.
        try await Self.draw(UsageView(usage: usage), shot: "ai-usage", tab: .usage, theme: "black", wait: .seconds(2))
    }

    /// The feed: a Claude Code session asking to run a command, others started and finished.
    @Test func agents() async throws {
        let hooks = AgentHooks(home: root.appending(path: "home"), support: root.appending(path: "support"))
        for tool in AgentTool.allCases {
            try FileManager.default.createDirectory(
                at: hooks.configFile(tool).deletingLastPathComponent(), withIntermediateDirectories: true)
            try hooks.install(tool)
        }
        let agents = AgentsFeature(hooks: hooks, defaults: UserDefaults(suiteName: "StoreTabShots-\(UUID())")!)
        agents.phase = .background
        let now = Date.now
        let writes: [(String, String, String, String, TimeInterval)] = [
            ("codex-photos", "working", "photo-sorter", "", -26 * 60),
            ("claude-recipes", "working", "recipe-box", "", -19 * 60),
            ("codex-photos", "waiting", "photo-sorter", "Wants to use exec_command", -15 * 60),
            ("codex-photos", "working", "photo-sorter", "", -14 * 60),
            ("claude-site", "working", "garden-blog", "", -8 * 60),
            ("claude-recipes", "done", "recipe-box", "", -3 * 60),
            ("codex-photos", "done", "photo-sorter", "", -60),
            ("claude-site", "waiting", "garden-blog", "Claude needs your permission to use Bash", -12),
        ]
        for (id, state, project, detail, offset) in writes {
            let file = hooks.states.appending(path: id)
            let lines = [state, "/Users/me/Code/\(project)", "com.apple.Terminal", "", "\(getpid())", detail, ""]
            try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: now + offset], ofItemAtPath: file.path)
            agents.reload(announcing: false)
        }
        try await Self.draw(agents.view, shot: "agents", tab: .agents, theme: "terminal")
        agents.phase = .stopped
    }

    /// A plan's limits as the dashboard shows them, with a little spend for the day.
    private static func plan(
        _ id: String, _ name: String, plan: String, session: Double, weekly: Double, resets: TimeInterval
    ) -> ProviderSnapshot {
        let now = Date.now
        return ProviderSnapshot(
            providerID: id, displayName: name, plan: plan,
            lines: [
                .progress(
                    label: "Session", used: session, limit: 100, format: .percent, resetsAt: now + resets,
                    periodDurationMs: 5 * 3_600_000),
                .progress(
                    label: "Weekly", used: weekly, limit: 100, format: .percent, resetsAt: now + 3 * 86_400,
                    periodDurationMs: 7 * 86_400_000),
                .values(label: "Today", values: [MetricValue(number: session / 12, kind: .dollars)]),
            ],
            refreshedAt: now - 180)
    }

    /// Draws `view` as the open notch lays out a tab in `theme`, on nothing, as NotchFeaturesTests'
    /// StoreTabShots.draw does.
    private static func draw(
        _ view: some View, shot: String, tab: FeatureID, theme id: String, wait: Duration = .seconds(1)
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
                $0.disablesAnimations = true
            }
        let host = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: notch), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
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

    private static func runLoop(for seconds: TimeInterval) {
        RunLoop.main.run(until: .now + seconds)
    }
}
