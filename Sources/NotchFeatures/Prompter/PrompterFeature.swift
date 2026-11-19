// SPDX-License-Identifier: MIT
import AVFoundation
import AppKit
import NotchCore
import Observation
import Speech
import SwiftUI
import UniformTypeIdentifiers

/// A teleprompter under the camera. The script moves on one word at a time: following your voice,
/// at a steady pace, or at a steady pace only while you speak. It moves only while its tab is on
/// screen, and pauses the moment the notch closes. The microphone is asked for the first time Voice
/// or Words starts, runs only while the script is moving, and nothing it hears is kept.
@MainActor
@Observable
public final class PrompterFeature: NotchFeature {
    public enum Mode: String, CaseIterable, Sendable {
        /// Follows the words you say, recognized on this Mac, and waits while you pause.
        case voice
        /// Moves on at a steady pace.
        case scroll
        /// Moves on at a steady pace while it hears you speak.
        case words

        public var title: String {
            switch self {
            case .voice: "Voice"
            case .scroll: "Scroll"
            case .words: "Words"
            }
        }

        public var symbol: String {
            switch self {
            case .voice: "mic"
            case .scroll: "arrow.down.to.line"
            case .words: "waveform"
            }
        }
    }

    /// Why the script stopped, or an import failed.
    public enum Problem: Equatable, Sendable {
        case microphone
        case speechRecognition
        case message(String)
    }

    public let id = FeatureID.prompter
    public var phase: FeaturePhase = .stopped {
        didSet { if phase != .foreground { pause() } }
    }

    public var script: String {
        didSet { defaults.set(script, forKey: Key.script) }
    }
    public var mode: Mode {
        didSet {
            defaults.set(mode.rawValue, forKey: Key.mode)
            if isRunning { move() }
        }
    }
    /// How fast Scroll and Words move, as a multiple of a speaking pace of 150 words a minute.
    public var speed: Double {
        didSet {
            defaults.set(speed, forKey: Key.speed)
            if isRunning { stepAlong() }
        }
    }
    public var textSize: Double {
        didSet { defaults.set(textSize, forKey: Key.textSize) }
    }
    /// Flipped left to right, for a teleprompter's glass.
    public var mirrored: Bool {
        didSet { defaults.set(mirrored, forKey: Key.mirrored) }
    }
    /// Whether screen sharing and recording leave the notch out while a script is up.
    public var hidesFromScreenSharing: Bool {
        didSet { defaults.set(hidesFromScreenSharing, forKey: Key.hidesFromScreenSharing) }
    }

    /// Showing the script to read, rather than the editor.
    public private(set) var isReading = false
    /// The script is moving.
    public private(set) var isRunning = false
    /// The next word to read.
    public private(set) var current = 0
    /// Where each word of the script is, in the text's UTF-16 offsets, while reading.
    public private(set) var wordRanges: [NSRange] = []
    /// Time spent reading, not counting pauses.
    public private(set) var stopwatch = Stopwatch()
    public private(set) var problem: Problem?

    /// Keeps the notch open, when a script starts and while a file is being picked.
    @ObservationIgnored public var keepOpen: (() -> Void)?
    /// Shows the closed notch that a script is under way, and how long is left; nil once it isn't.
    @ObservationIgnored public var onOngoing: ((Activity?) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let listener = SpeechListener()
    @ObservationIgnored private var alignment = ScriptAlignment([])
    @ObservationIgnored private var words: [String] = []
    @ObservationIgnored private var step: Task<Void, Never>?
    @ObservationIgnored private var speaking = false

    /// A comfortable speaking pace: 150 words a minute.
    public static let wordsPerSecond = 2.5
    public static let speeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3]
    public static let textSizes: ClosedRange<Double> = 16...40

    private enum Key {
        static let script = "prompter.script"
        static let mode = "prompter.mode"
        static let speed = "prompter.speed"
        static let textSize = "prompter.textSize"
        static let mirrored = "prompter.mirrored"
        static let hidesFromScreenSharing = "prompter.hidesFromScreenSharing"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        script = defaults.string(forKey: Key.script) ?? ""
        mode = defaults.string(forKey: Key.mode).flatMap(Mode.init(rawValue:)) ?? .voice
        speed = defaults.object(forKey: Key.speed) as? Double ?? 1
        textSize = defaults.object(forKey: Key.textSize) as? Double ?? 24
        mirrored = defaults.bool(forKey: Key.mirrored)
        hidesFromScreenSharing = defaults.object(forKey: Key.hidesFromScreenSharing) as? Bool ?? true
        listener.onTranscript = { [weak self] in self?.heard($0) }
        listener.onRestart = { [weak self] in
            guard let self else { return }
            alignment = ScriptAlignment(words, at: current)
        }
        listener.onSpeaking = { [weak self] in
            self?.speaking = $0
            self?.stepAlong()
        }
        listener.onFailure = { [weak self] in self?.stop(.message($0)) }
    }

    public var view: some View { PrompterView(prompter: self) }

    /// Whether the last word has been read.
    public var isFinished: Bool { isReading && current >= wordRanges.count }

    /// Roughly how long the rest takes to read: at the speed set, or in Voice mode at the pace you've
    /// been reading once there's enough to tell.
    public func remaining(at date: Date = .now) -> TimeInterval {
        let elapsed = stopwatch.elapsed(at: date)
        var pace = Self.wordsPerSecond * (mode == .voice ? 1 : speed)
        if mode == .voice, current >= 20, elapsed >= 10 { pace = Double(current) / elapsed }
        return Double(max(wordRanges.count - current, 0)) / pace
    }

    // MARK: Reading

    /// Starts the script from the top, or carries on after a pause. It moves only while on screen.
    public func start() {
        guard phase == .foreground, !isRunning else { return }
        if !isReading {
            wordRanges = script.ranges(of: /\S+/).map { NSRange($0, in: script) }
            words = wordRanges.map { (script as NSString).substring(with: $0) }
            guard !words.isEmpty else { return }
            alignment = ScriptAlignment(words)
            current = 0
            stopwatch.reset()
            isReading = true
        }
        guard !isFinished else { return }
        problem = nil
        isRunning = true
        stopwatch.start(at: .now)
        keepOpen?()
        move()
        publish()
    }

    public func pause() {
        guard isRunning else { return }
        isRunning = false
        stopwatch.pause(at: .now)
        move()
        publish()
    }

    public func toggle() { isRunning ? pause() : start() }

    /// Back to the first word.
    public func restart() {
        current = 0
        stopwatch.reset()
        if isRunning {
            stopwatch.start(at: .now)
            listener.stop()  // a fresh transcript for the top of the script
            move()
        }
        publish()
    }

    /// Back to the editor.
    public func edit() {
        pause()
        isReading = false
        wordRanges = []
        words = []
        current = 0
        stopwatch.reset()
        problem = nil
        publish()
    }

    /// Stops the script because something's in the way, such as a permission that's off.
    private func stop(_ problem: Problem) {
        pause()
        self.problem = problem
    }

    /// Sets the script moving the way the mode says, or stops everything once it's paused. A fresh
    /// microphone hasn't heard anyone yet, so Words waits for speech again.
    private func move() {
        speaking = false
        stepAlong()
        if isRunning, mode != .scroll { listen() } else { listener.stop() }
    }

    /// Moves on a word at a time at the speed set: always in Scroll mode, while speaking in Words.
    private func stepAlong() {
        step?.cancel()
        step = nil
        guard isRunning, mode == .scroll || (mode == .words && speaking) else { return }
        let interval = 1 / (Self.wordsPerSecond * speed)
        step = Task { [weak self] in
            while true {
                do { try await Task.sleep(for: .seconds(interval), tolerance: .milliseconds(20)) } catch { return }
                guard let self else { return }
                advance(to: current + 1)
            }
        }
    }

    private func heard(_ transcript: String) {
        guard isRunning, mode == .voice else { return }
        advance(to: alignment.match(transcript))
    }

    private func advance(to index: Int) {
        guard isRunning, index > current else { return }
        current = min(index, wordRanges.count)
        if isFinished { pause() }
    }

    /// The microphone, asking for it (and for speech recognition in Voice mode) the first time.
    private func listen() {
        let recognizing = mode == .voice
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined: return Self.askForMicrophone { [weak self] in self?.move() }
        default: return stop(.microphone)
        }
        if recognizing {
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: break
            case .notDetermined: return Self.askForSpeechRecognition { [weak self] in self?.move() }
            default: return stop(.speechRecognition)
            }
        }
        listener.start(recognizing: recognizing) { [weak self] in self?.hints ?? [] }
    }

    /// Longer words the script says next, which help the recognizer with names and jargon.
    private var hints: [String] {
        var seen: Set<String> = []
        return Array(alignment.words.dropFirst(current).filter { $0.count >= 5 && seen.insert($0).inserted }.prefix(50))
    }

    // Built outside the main actor: macOS answers these on a queue of its own.
    private nonisolated static func askForMicrophone(then: @escaping @MainActor @Sendable () -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { _ in Task { @MainActor in then() } }
    }

    private nonisolated static func askForSpeechRecognition(then: @escaping @MainActor @Sendable () -> Void) {
        SFSpeechRecognizer.requestAuthorization { _ in Task { @MainActor in then() } }
    }

    /// The closed notch shows a script under way, with the time it has left.
    private func publish() {
        guard isReading, !isFinished else {
            onOngoing?(nil)
            return
        }
        let left = remaining()
        onOngoing?(
            Activity(
                feature: .prompter, symbol: FeatureID.prompter.symbol, title: "\(formatTime(left)) left",
                duration: .zero, countdown: isRunning ? Date.now.addingTimeInterval(left) : nil))
    }

    // MARK: Importing

    /// Picks a text, Markdown, or PowerPoint file and makes it the script.
    public func importScript() {
        keepOpen?()
        let panel = NSOpenPanel()
        let deck = UTType("org.openxmlformats.presentationml.presentation")
        panel.allowedContentTypes = [.plainText] + [deck].compactMap { $0 }
        panel.message = "Choose a script: a text or Markdown file, or a PowerPoint deck's speaker notes."
        panel.prompt = "Import"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await load(url) }
    }

    func load(_ url: URL) async {
        do {
            switch url.pathExtension.lowercased() {
            case "pptx":
                script = try await PresentationNotes.slides(in: url).joined(separator: "\n\n")
            case "md", "markdown":
                var encoding = String.Encoding.utf8
                script = Self.plainText(markdown: try String(contentsOf: url, usedEncoding: &encoding))
            default:
                var encoding = String.Encoding.utf8
                script = try String(contentsOf: url, usedEncoding: &encoding)
            }
            problem = nil
        } catch {
            problem = .message(error.localizedDescription)
        }
    }

    /// Markdown as it's read aloud: no emphasis marks or link targets, and no heading, list, or quote
    /// marks at the start of a line.
    nonisolated static func plainText(markdown: String) -> String {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let inline = (try? AttributedString(markdown: markdown, options: options)).map { String($0.characters) }
        return (inline ?? markdown).replacing(/^ {0,3}(?:#{1,6}|[-*+>]) +/.anchorsMatchLineEndings(), with: "")
    }
}
