// SPDX-License-Identifier: MIT
// Adapted from Textream (https://github.com/f/textream) at 2c02f3e: SpeechRecognizer's capture and
// recognition (a mono tap at the input's own sample rate, partial results, hints from the script,
// a fresh task before the recognizer's one-minute limit and after it gives up), and
// VoiceActivityDetector.
// Copyright (c) 2026 Fatih Kadir Akin. MIT License; see THIRD_PARTY_NOTICES.md.
import AVFoundation
import NotchCore
import Speech

/// The prompter's microphone: whether someone is speaking and, when asked, the words they say,
/// recognized on this Mac only. It listens from `start` until `stop`; nothing is recorded or kept.
@MainActor
final class SpeechListener {
    /// Whether a voice is speaking, each time that changes.
    var onSpeaking: ((Bool) -> Void)?
    /// Everything heard since the last `onRestart`: the recognizer's best guess so far.
    var onTranscript: ((String) -> Void)?
    /// A new recognition task began, so its transcript starts from nothing.
    var onRestart: (() -> Void)?
    /// Listening stopped for good, and why.
    var onFailure: ((String) -> Void)?

    private var engine: AVAudioEngine?
    private var feed: AudioFeed?
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    /// Words the script says next, which help the recognizer spell names and jargon.
    private var hints: () -> [String] = { [] }
    private var renewal: Task<Void, Never>?
    private var configuration: NSObjectProtocol?
    /// Results from a task that's been replaced are ignored.
    private var generation = 0
    /// And so is the speaking of a microphone that's been stopped.
    private var session = 0
    /// Recognition failures in a row, other than the recognizer timing out.
    private var failures = 0

    var isListening: Bool { engine != nil }

    /// Starts the microphone; with `recognizing`, follows the words too.
    func start(recognizing: Bool, hints: @escaping () -> [String]) {
        stop()
        self.hints = hints
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let hardware = input.outputFormat(forBus: 0)
        // The tap has to run at the input's own rate; it can only mix the channels down to the mono
        // the recognizer wants.
        guard hardware.sampleRate > 0, hardware.channelCount > 0,
            let format = hardware.channelCount == 1
                ? hardware
                : AVAudioFormat(
                    commonFormat: .pcmFormatFloat32, sampleRate: hardware.sampleRate, channels: 1, interleaved: false)
        else { return fail("There's no microphone to listen with.") }
        let session = session
        let feed = AudioFeed { [weak self] speaking in
            Task { @MainActor in
                guard let self, self.session == session else { return }
                self.onSpeaking?(speaking)
            }
        }
        self.feed = feed
        self.engine = engine
        if recognizing {
            guard let recognizer = SFSpeechRecognizer(), recognizer.supportsOnDeviceRecognition else {
                let language =
                    Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? "your language"
                return fail(
                    "This Mac can't recognize \(language) on its own. Use Scroll or Words, or turn on Dictation "
                        + "in System Settings › Keyboard.")
            }
            self.recognizer = recognizer
            recognize()
        }
        input.installTap(
            onBus: 0, bufferSize: AVAudioFrameCount(max(1024, hardware.sampleRate / 40)), format: format,
            block: Self.tap(into: feed))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            return fail("The microphone didn't start: \(error.localizedDescription)")
        }
        // Another microphone was picked or plugged in: start over on it.
        configuration = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isListening else { return }
                self.start(recognizing: self.recognizer != nil, hints: self.hints)
            }
        }
        Log.features.info("Prompter microphone on\(recognizing ? ", following words" : "", privacy: .public)")
    }

    /// Stops the microphone at once.
    func stop() {
        generation += 1
        session += 1
        renewal?.cancel()
        renewal = nil
        feed?.use(nil)
        task?.cancel()
        task = nil
        recognizer = nil
        if let configuration { NotificationCenter.default.removeObserver(configuration) }
        configuration = nil
        guard let engine else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        self.engine = nil
        feed = nil
        Log.features.info("Prompter microphone off")
    }

    private func fail(_ message: String) {
        stop()
        onFailure?(message)
    }

    /// A fresh recognition task on the running microphone, renewed before the recognizer's limit.
    private func recognize() {
        guard let recognizer, let feed else { return }
        generation += 1
        task?.cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true  // never leaves this Mac
        request.taskHint = .dictation
        request.contextualStrings = hints()
        feed.use(request)
        let handler = Self.results(generation) { [weak self] in self?.received($0, generation: $1) }
        task = recognizer.recognitionTask(with: request, resultHandler: handler)
        onRestart?()
        renewal?.cancel()
        renewal = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(55)) } catch { return }
            self?.recognize()
        }
    }

    private func received(_ result: RecognitionResult, generation: Int) {
        guard generation == self.generation else { return }
        if let text = result.text {
            failures = 0
            onTranscript?(text)
        }
        guard result.ended else { return }
        // 1110: no speech for a while, and 216: the recognizer's time ran out. Both are routine.
        if let code = result.errorCode, ![1110, 216].contains(code) {
            failures += 1
            guard failures <= 3 else {
                return fail("Speech recognition stopped: \(result.errorMessage ?? "error \(code)")")
            }
        }
        recognize()
    }

    /// What one recognition callback says, made Sendable to carry it to the main actor.
    private struct RecognitionResult: Sendable {
        var text: String?
        var ended: Bool
        var errorCode: Int?
        var errorMessage: String?
    }

    /// Built outside the main actor: the recognizer may call back on any queue.
    private nonisolated static func results(
        _ generation: Int, _ deliver: @escaping @MainActor @Sendable (RecognitionResult, Int) -> Void
    ) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            let error = error as NSError?
            let received = RecognitionResult(
                text: result?.bestTranscription.formattedString, ended: error != nil || result?.isFinal == true,
                errorCode: error?.code, errorMessage: error?.localizedDescription)
            Task { @MainActor in deliver(received, generation) }
        }
    }

    /// Built outside the main actor: Core Audio calls it on its own real-time thread.
    private nonisolated static func tap(into feed: AudioFeed) -> AVAudioNodeTapBlock {
        { buffer, _ in feed.receive(buffer) }
    }
}

/// Hands the microphone's buffers to the current recognition request and tracks whether someone is
/// speaking. Called on Core Audio's thread; the lock covers the request swapping under it.
private final class AudioFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var detector = VoiceActivityDetector()
    private var speaking = false
    private let onSpeaking: @Sendable (Bool) -> Void

    init(onSpeaking: @escaping @Sendable (Bool) -> Void) { self.onSpeaking = onSpeaking }

    /// The request that gets the audio from now on; the old one is told its audio ended.
    func use(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request?.endAudio()
        self.request = request
        lock.unlock()
    }

    func receive(_ buffer: AVAudioPCMBuffer) {
        let level = Self.level(of: buffer)
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        request?.append(buffer)
        detector.process(level: level, at: now)
        let active = detector.isActive(at: now)
        let changed = active != speaking
        speaking = active
        lock.unlock()
        if changed { onSpeaking(active) }
    }

    /// Loudness 0...1: the first channel's RMS, scaled as Textream's detector thresholds expect.
    private static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count { sum += samples[index] * samples[index] }
        return min(Double((sum / Float(count)).squareRoot()) * 5, 1)
    }
}

/// Whether someone is speaking, from loudness: a loud moment counts at once, a quieter one only when
/// the next is too, and speech lasts three quarters of a second past the last loud moment, so the
/// gaps between words don't count as pauses.
struct VoiceActivityDetector {
    // ponytail: Textream's thresholds, tuned on built-in microphones; a sensitivity setting if
    // headsets or noisy rooms need one.
    private let activation = 0.012
    private let immediateActivation = 0.04
    private let requiredFrames = 2
    private let hangover: TimeInterval = 0.75
    private var activeFrames = 0
    private var activeUntil = -TimeInterval.infinity

    mutating func process(level: Double, at time: TimeInterval) {
        if level >= immediateActivation {
            activeFrames = requiredFrames
            activeUntil = max(activeUntil, time + hangover)
        } else if level >= activation {
            activeFrames += 1
            if activeFrames >= requiredFrames { activeUntil = max(activeUntil, time + hangover) }
        } else {
            activeFrames = 0
        }
    }

    func isActive(at time: TimeInterval) -> Bool { time < activeUntil }
}
