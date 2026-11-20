// SPDX-License-Identifier: MIT
import AppKit
import NotchTheme
import SwiftUI
import Testing

@testable import NotchUsage

/// The Agents tab's timeline: what the hooks wrote, as events, and the tab drawing them in each look.
@MainActor
struct AgentsActivityTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "AgentsActivity-\(UUID())")
    private var hooks: AgentHooks {
        AgentHooks(home: root.appending(path: "home"), support: root.appending(path: "support"))
    }

    /// A feature watching a throwaway folder, with both tools connected.
    private func feature() throws -> AgentsFeature {
        for tool in AgentTool.allCases {
            try FileManager.default.createDirectory(
                at: hooks.configFile(tool).deletingLastPathComponent(), withIntermediateDirectories: true)
            try hooks.install(tool)
        }
        let agents = AgentsFeature(hooks: hooks, defaults: UserDefaults(suiteName: "AA.\(UUID().uuidString)")!)
        agents.phase = .background
        return agents
    }

    /// A session file as the hook script writes it, written at `time`.
    private func write(_ id: String, _ state: String, project: String, detail: String = "", at time: Date) throws {
        let file = hooks.states.appending(path: id)
        let lines = [state, "/Users/me/Code/\(project)", "com.apple.Terminal", "", "\(getpid())", detail, ""]
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: file.path)
    }

    @Test func eachWriteIsAnEventButAnAnsweredAskIsnt() throws {
        let agents = try feature()
        let start = Date.now.addingTimeInterval(-900)
        try write("claude-a", "working", project: "nook", at: start)
        agents.reload(announcing: false)
        let bash = "Claude needs your permission to use Bash"
        try write("claude-a", "waiting", project: "nook", detail: bash, at: start + 60)
        agents.reload(announcing: false)
        let ask = try #require(agents.events.first)
        #expect(ask.kind == .asked && ask.request == "use Bash" && agents.needsYou(ask))

        try write("claude-a", "working", project: "nook", at: start + 90)  // answered
        agents.reload(announcing: false)
        #expect(agents.events.map(\.kind) == [.asked, .started], "an answer only stops the ask waiting")
        #expect(!agents.needsYou(ask))

        try write("claude-a", "done", project: "nook", at: start + 660)
        agents.reload(announcing: false)
        agents.reload(announcing: false)  // nothing new
        #expect(agents.events.map(\.kind) == [.finished, .asked, .started])
        #expect(agents.events.first?.took == 660, "from its start")

        for index in 0..<60 {
            try write("codex-\(index)", "working", project: "p\(index)", at: start + 700 + Double(index))
        }
        agents.reload(announcing: false)
        #expect(agents.events.count == 50 && agents.events.first?.project == "p59", "the newest 50")

        agents.phase = .stopped
        #expect(agents.events.isEmpty, "stopped, it lets go")
    }

    /// The feed in Black, Paper, and Terminal (or `AUDIT_THEME` alone), at the default size and the
    /// smallest; with SNAPSHOT_DIR set, PNGs in a folder per theme there.
    @Test func theFeedReadsInEachLook() throws {
        let agents = try feature()
        let now = Date.now
        let writes: [(String, String, String, String, TimeInterval)] = [
            ("codex-api", "working", "api-server", "", -21 * 60),
            ("claude-site", "working", "simplideliver-website", "", -13 * 60),
            ("codex-api", "waiting", "api-server", "Wants to use exec_command", -12 * 60),
            ("codex-api", "working", "api-server", "", -11 * 60),
            ("claude-nook", "working", "ilovenotch", "", -9 * 60),
            ("claude-site", "done", "simplideliver-website", "", -2 * 60),
            ("claude-nook", "waiting", "ilovenotch", "Claude needs your permission to use Bash", -10),
        ]
        for (id, state, project, detail, offset) in writes {
            try write(id, state, project: project, detail: detail, at: now + offset)
            agents.reload(announcing: false)
        }
        #expect(agents.events.count == 6 && agents.events.first.map(agents.needsYou) == true)

        let audit = ProcessInfo.processInfo.environment["AUDIT_THEME"]
        for id in audit.map({ [$0] }) ?? ["black", "paper", "terminal"] {
            let theme = Themes.theme(id)
            try render(agents.view, theme: theme, name: "\(id)/agents", size: CGSize(width: 396, height: 192))
            try render(agents.view, theme: theme, name: "\(id)/agents-smallest", size: CGSize(width: 350, height: 102))
        }
        agents.phase = .stopped
    }

    private func render(_ view: some View, theme: Theme, name: String, size: CGSize) throws {
        let framed = view.frame(width: size.width, height: size.height).padding(16)
            .background(theme.surface.color.color)
            .foregroundStyle(.themeInk)
            .environment(\.colorScheme, theme.appearance.colorScheme)
            .environment(\.theme, theme)
        let host = NSHostingView(rootView: framed)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: CGSize(width: size.width + 32, height: size.height + 32)),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0)
        if let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] {
            let file = URL(filePath: directory).appending(path: "\(name).png")
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])?.write(to: file)
        }
    }
}
