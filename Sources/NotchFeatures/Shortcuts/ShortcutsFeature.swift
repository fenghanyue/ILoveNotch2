// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import Observation
import SwiftUI

/// Runs the user's Shortcuts from the notch through the public `shortcuts` command-line tool, so
/// they run in the background without bringing the Shortcuts app forward. Four favorites sit on
/// pads, and a log keeps what the last runs did.
@MainActor
@Observable
public final class ShortcutsFeature: NotchFeature {
    public enum Status: Equatable, Sendable { case loading, ready, unavailable }

    /// One run in the log.
    public struct Run: Identifiable, Equatable, Sendable {
        public enum Outcome: Equatable, Sendable {
            case running, done, stopped
            /// With the first line the tool printed about it, if any.
            case failed(String?)
        }

        public let id = UUID()
        public let name: String
        public let started: Date
        public internal(set) var ended: Date?
        public internal(set) var outcome = Outcome.running
        /// What the shortcut gave back, when it's text.
        public internal(set) var output: String?
        /// Whether its output was copied from the log.
        public internal(set) var copied = false

        public var duration: TimeInterval? { ended.map { $0.timeIntervalSince(started) } }
    }

    public let id = FeatureID.shortcuts
    public var phase: FeaturePhase = .stopped {
        didSet {
            guard phase != oldValue else { return }
            if phase == .foreground { refresh() }
            if phase == .stopped {
                shortcuts = []
                status = .loading
            }
        }
    }
    public internal(set) var shortcuts: [String] = []
    public internal(set) var status = Status.loading
    public private(set) var running: Set<String> = []
    /// The last runs, newest first; kept while the app runs.
    public internal(set) var log: [Run] = []
    /// Shortcuts the user chose not to show in the notch.
    public var hidden: Set<String> {
        didSet { defaults.set(hidden.sorted(), forKey: Self.hiddenKey) }
    }
    /// The favorites the user picked, in pad order; nil until they pick.
    private var pinned: [String]? {
        didSet { defaults.set(pinned, forKey: Self.favoritesKey) }
    }
    /// Raised when a shortcut finishes.
    @ObservationIgnored public var onActivity: ((Activity) -> Void)?

    static let tool = "/usr/bin/shortcuts"
    static let favoriteCount = 4
    static let logLength = 20
    private static let hiddenKey = "shortcuts.hidden"
    private static let favoritesKey = "shortcuts.favorites"
    @ObservationIgnored private let defaults: UserDefaults
    /// The command-line tool; tests swap in one that answers at once.
    @ObservationIgnored private let executable: String
    /// What each running entry runs in, so it can be stopped.
    @ObservationIgnored private var processes: [Run.ID: Process] = [:]

    public convenience init(defaults: UserDefaults = .standard) {
        self.init(defaults: defaults, executable: Self.tool)
    }

    init(defaults: UserDefaults, executable: String) {
        self.defaults = defaults
        self.executable = executable
        hidden = Set(defaults.stringArray(forKey: Self.hiddenKey) ?? [])
        pinned = defaults.stringArray(forKey: Self.favoritesKey)
    }

    public var view: some View { ShortcutsView(shortcuts: self) }

    public var visible: [String] { shortcuts.filter { !hidden.contains($0) } }

    /// The pads: the shortcuts the user pinned that are still shown, or the first four until they pick.
    public var favorites: [String] {
        guard let pinned else { return Array(visible.prefix(Self.favoriteCount)) }
        let shown = Set(visible)
        return pinned.filter(shown.contains)
    }

    public func pin(_ name: String) {
        guard !favorites.contains(name), favorites.count < Self.favoriteCount else { return }
        pinned = favorites + [name]
    }

    public func unpin(_ name: String) {
        pinned = favorites.filter { $0 != name }
    }

    /// Puts `other` on `name`'s pad.
    public func replace(_ name: String, with other: String) {
        guard !favorites.contains(other) else { return }
        pinned = favorites.map { $0 == name ? other : $0 }
    }

    /// The newest run of `name` in the log.
    public func lastRun(of name: String) -> Run? { log.first { $0.name == name } }

    /// Lists the user's shortcuts; called when the tab or its settings come on screen.
    public func refresh() {
        Task {
            let (status, output) = await Subprocess.run(executable, ["list"])
            guard phase != .stopped else { return }  // stopped while listing: stay released
            guard status == 0 else {
                self.status = .unavailable
                return
            }
            shortcuts = Self.parseList(output)
            self.status = .ready
        }
    }

    public func run(_ name: String) {
        guard !running.contains(name) else { return }
        running.insert(name)
        let run = Run(name: name, started: .now)
        log.insert(run, at: 0)
        if log.count > Self.logLength { log.removeLast(log.count - Self.logLength) }
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = ["run", name]
        processes[run.id] = process
        Task {
            let (status, output, error) = await Self.execute(process)
            processes[run.id] = nil
            running.remove(name)
            let done = status == 0
            if let index = log.firstIndex(where: { $0.id == run.id }) {
                log[index].ended = .now
                let text = output?.trimmingCharacters(in: .whitespacesAndNewlines)
                log[index].output = text?.isEmpty == false ? text : nil
                guard log[index].outcome == .running else { return }  // stopped: the user knows
                log[index].outcome = done ? .done : .failed(Self.reason(error))
            }
            onActivity?(
                Activity(
                    feature: .shortcuts,
                    symbol: done ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    title: done ? name : "\(name) failed",
                    duration: .seconds(2)))
        }
    }

    /// Stops a run the way Control-C does in Terminal: the tool cancels the shortcut and exits.
    public func stop(_ id: Run.ID) {
        guard let process = processes[id], process.isRunning,
            let index = log.firstIndex(where: { $0.id == id })
        else { return }
        log[index].outcome = .stopped
        process.interrupt()
    }

    /// Copies a run's output again, and marks it copied.
    public func copyOutput(of id: Run.ID) {
        guard let index = log.firstIndex(where: { $0.id == id }), let output = log[index].output else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        log[index].copied = true
    }

    /// Clears the finished runs; running ones stay, so they can still be stopped.
    public func clearLog() {
        log.removeAll { $0.outcome != .running }
    }

    public func openShortcutsApp() {
        let workspace = NSWorkspace.shared
        guard let app = workspace.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") else { return }
        workspace.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// One shortcut name per line, sorted the way Finder sorts names.
    static func parseList(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The tool's first error line, without its "Error: ".
    static func reason(_ error: String?) -> String? {
        guard let line = error?.split(whereSeparator: \.isNewline).first else { return nil }
        let text = line.trimmingCharacters(in: .whitespaces)
        return text.hasPrefix("Error: ") ? String(text.dropFirst(7)) : text
    }

    /// Runs `process` to completion off the main thread: its exit status, its output when that's
    /// text (an image comes back as nil), and what it printed as an error.
    nonisolated private static func execute(_ process: Process) async -> (Int32, String?, String?) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: (-1, nil, nil))
                    return
                }
                // Drain before waiting, or a chatty tool fills the pipe and never exits.
                // ponytail: errors are read after the output, so a tool that wrote over 64 KB of errors
                // first would stall; shortcuts writes one line. Read both at once if that changes.
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                let message = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(
                    returning: (
                        process.terminationStatus, String(data: data, encoding: .utf8),
                        String(data: message, encoding: .utf8)
                    ))
            }
        }
    }
}
