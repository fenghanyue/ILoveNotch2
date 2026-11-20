// SPDX-License-Identifier: MIT
import NotchTheme
import SwiftUI

/// The timer tab. A countdown shows as a dial: a ring that drains as it runs, with when it rings,
/// the time left, and its length inside, and the presets around it like the hours on a clock face,
/// the running one marked. Beside the dial sit the switch between Timer, Stopwatch, and Keep Awake,
/// the countdown's controls, and a field for any other length. The stopwatch and keep awake show
/// their time where the dial is and their controls beside it. A shorter notch draws the ring alone
/// and moves the presets beside it.
struct TimerView: View {
    let timer: TimerFeature

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// What's typed in the minutes field.
    @State private var minutes = ""

    var body: some View {
        GeometryReader { proxy in
            let dial = Dial(fitting: proxy.size, reach: ringStyle.reach)
            HStack(alignment: .top, spacing: Dial.gap) {
                Group {
                    switch timer.mode {
                    case .countdown: countdownDial(dial)
                    case .stopwatch: stopwatchClock(large: dial.ringed)
                    case .keepAwake: awakeClock(large: dial.ringed)
                    }
                }
                .frame(width: dial.width, height: proxy.size.height)
                VStack(alignment: .leading, spacing: dial.ringed ? 12 : 6) {
                    modeSwitch
                    Group {
                        switch timer.mode {
                        case .countdown:
                            if dial.ringed { countdownColumn } else { compactCountdownColumn }
                        case .stopwatch: stopwatchColumn
                        case .keepAwake: awakeColumn
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .background { undoSwapKey }
    }

    private var ringStyle: RingStyle { RingStyle(theme) }

    /// Whether the accent glows: on a dark sheet, without Reduce Transparency.
    private var glows: Bool { theme.appearance == .dark && !reduceTransparency }

    /// The accent's glow at `strength`, or clear where it doesn't glow: a shadow draws even at no
    /// radius, a copy that shows through anything faded over it.
    private func glow(_ strength: Double) -> Color { glows ? theme.color(.accent).opacity(strength) : .clear }

    // MARK: Switch

    /// Timer, Stopwatch, and Keep Awake, ⌘1 to ⌘3; Keep Awake's cup lights while the Mac is kept
    /// awake. A narrow column shortens Keep Awake to Awake.
    private var modeSwitch: some View {
        ViewThatFits(in: .horizontal) {
            modeSwitch(awake: "Keep Awake")
            modeSwitch(awake: "Awake")
        }
    }

    private func modeSwitch(awake: String) -> some View {
        HStack(spacing: 2) {
            modeButton("Timer", .countdown, key: "1")
            modeButton("Stopwatch", .stopwatch, key: "2")
            modeButton(awake, .keepAwake, key: "3", lit: timer.keepsAwake)
        }
        .padding(2)
        .themePlatter(0.08, in: RoundedRectangle(cornerRadius: theme.controls?.radius ?? 9, style: .continuous))
    }

    /// `lit` marks a mode that's running while another is showing.
    private func modeButton(_ title: String, _ mode: TimerFeature.Mode, key: KeyEquivalent, lit: Bool = false)
        -> some View
    {
        let chosen = timer.mode == mode
        let radius = max(0, (theme.controls?.radius ?? 9) - 2)
        return Button {
            timer.mode = mode
        } label: {
            HStack(spacing: 4) {
                if lit {
                    let cup = ThemeSymbol("cup.and.saucer.fill").themeFont(.body, size: 10)
                    if chosen { cup } else { cup.foregroundStyle(.themeAccent) }
                }
                Text(title)
            }
            .fixedSize()
            .themeFont(.body, size: 11.5, weight: .semibold)
            .themeSelectionInk(chosen, unlit: 0.62)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 24)
            .background {
                if chosen { SelectionMark(in: RoundedRectangle(cornerRadius: radius, style: .continuous)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: .command)
        .accessibilityLabel(lit ? "\(title), on" : title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    // MARK: Dial

    /// The dial. The ring and the time inside redraw once a second while the countdown runs on
    /// screen, without animating each step; starting, swapping, or changing a countdown sweeps the
    /// ring to its new length in 0.4 s, except with Reduce Motion.
    private func countdownDial(_ dial: Dial) -> some View {
        let countdown = timer.countdown
        return ZStack {
            if ringStyle == .arc, glows, countdown?.isRunning == true {
                // Soft light behind a running dial, past its frame so it never ends in an edge.
                RadialGradient(
                    colors: [theme.color(.accent).opacity(0.24), .clear], center: .center, startRadius: 0,
                    endRadius: dial.radius * 1.7
                )
                .padding(-dial.radius)
                .allowsHitTesting(false)
            }
            TimelineView(Self.ticks(countdown)) { context in
                let left = countdown.map { min($0.total, $0.remaining(at: context.date)) } ?? 0
                ZStack {
                    ring(lit: countdown.map { $0.total > 0 ? left / $0.total : 0 } ?? 0, dial)
                    dialCenter(countdown, left: left, dial)
                }
            }
            if dial.ringed {
                ForEach(Array(TimerFeature.presets.enumerated()), id: \.element) { index, seconds in
                    let angle = Double(index) * .pi / 4
                    preset(seconds)
                        .frame(width: Dial.chip.width, height: Dial.chip.height)
                        .position(
                            x: dial.width / 2 + dial.presetRadius * sin(angle),
                            y: dial.height / 2 - dial.presetRadius * cos(angle))
                }
            }
        }
        .frame(width: dial.width, height: dial.height)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: countdown)
    }

    /// Once a second while the countdown runs, just after each second turns so the digits change
    /// on time; hourly otherwise, which changes nothing.
    private static func ticks(_ countdown: Countdown?) -> PeriodicTimelineSchedule {
        guard let countdown, let end = countdown.endsAt else { return .periodic(from: .now, by: 3600) }
        return .periodic(from: end.addingTimeInterval(-countdown.total - 0.99), by: 1)
    }

    /// The ring in the theme's style, `lit` (0...1) of it in the accent from the top, clockwise.
    @ViewBuilder private func ring(lit: Double, _ dial: Dial) -> some View {
        let lit = min(max(lit, 0), 1)
        let line = ringStyle.line * dial.scale
        let side = dial.radius * 2
        switch ringStyle {
        case .arc:
            ZStack {
                Circle().stroke(.themeInk.opacity(0.12), lineWidth: line)
                Circle().trim(from: 0, to: lit).rotation(.degrees(-90))
                    .stroke(.themeAccent, style: StrokeStyle(lineWidth: line, lineCap: theme.seekBar.cap.lineCap))
                    .shadow(color: glow(0.7), radius: 8 * dial.scale)
                    .opacity(lit > 0 ? 1 : 0)  // a round end draws a dot for nothing
            }
            .frame(width: side, height: side)
        case .printed:
            ZStack {
                Ticks(
                    inner: dial.radius + 8 * dial.scale, minor: dial.radius + 11 * dial.scale,
                    major: dial.radius + 13 * dial.scale
                )
                .stroke(.themeInk.opacity(0.45), lineWidth: 1)
                Circle().stroke(.themeInk.opacity(0.32), lineWidth: 1).frame(width: side, height: side)
                Circle().trim(from: 0, to: lit).rotation(.degrees(-90))
                    .stroke(.themeAccent, lineWidth: line)
                    .frame(width: side, height: side)
            }
        case .blocks:
            let style = StrokeStyle(lineWidth: line)
            ZStack {
                BlockRing(lit: 1).stroke(.themeInk.opacity(0.22), style: style)
                BlockRing(lit: lit).stroke(.themeAccent, style: style)
                    .shadow(color: glow(0.55), radius: 5 * dial.scale)
                if theme.appearance == .light {
                    // A pale accent on a light sheet takes an edge in the ink.
                    BlockRing(lit: lit).stroke(style: style).stroke(.themeInk, lineWidth: 1.5)
                }
            }
            .frame(width: side, height: side)
        }
    }

    /// When the countdown rings, the time left, and its length, inside the ring; with no countdown,
    /// a prompt to pick one.
    private func dialCenter(_ countdown: Countdown?, left: TimeInterval, _ dial: Dial) -> some View {
        let small = max(10, 11 * dial.scale)
        // Inside the ring's line; the lines above and below the digits, where the ring is narrower.
        let inside = max(0, 2 * dial.radius - ringStyle.line * dial.scale)
        let label =
            if let countdown {
                (countdown.isRunning ? "" : "Paused, ")
                    + "\(Self.spoken(left)) left of a \(Self.spoken(countdown.total)) timer"
            } else {
                "No timer running"
            }
        return VStack(spacing: 2 * dial.scale) {
            Group {
                if let end = countdown?.endsAt {
                    HStack(spacing: 3) {
                        ThemeSymbol("bell").themeFont(.body, size: small - 1, weight: .semibold)
                        Text(Self.clock(end))
                    }
                } else if countdown != nil {
                    Text("Paused")
                }
            }
            .themeFont(.body, size: small, weight: .semibold)
            .foregroundStyle(.themeInk.opacity(0.62))
            .frame(maxWidth: inside * 0.7)
            Text(formatTime(left))
                .themeFont(.display, size: ringStyle.digits * dial.scale, weight: .semibold, design: .rounded)
                .monospacedDigit()
                .opacity(countdown == nil ? 0.3 : countdown?.isRunning == true ? 1 : 0.5)
                // A terminal's numbers glow like phosphor.
                .shadow(color: ringStyle == .blocks ? glow(0.5) : .clear, radius: 6)
            Text(countdown.map { "left of \(Self.length($0.total))" } ?? "Pick a time")
                .themeFont(.body, size: small)
                .foregroundStyle(.themeInk.opacity(0.62))
                .frame(maxWidth: inside * 0.7)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(width: inside * 0.84)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// A preset around the dial: it starts its countdown, or swaps it for the running one (⌘Z
    /// swaps back), and is marked while it runs. Around a printed dial it's a numeral, like an hour
    /// on a clock face; elsewhere a chip.
    private func preset(_ seconds: TimeInterval) -> some View {
        let lit = timer.countdown?.total == seconds
        let printed = ringStyle == .printed
        let shape = RoundedRectangle(cornerRadius: theme.controls?.radius ?? Dial.chip.height / 2, style: .continuous)
        return Button {
            timer.start(seconds)
        } label: {
            Text(Self.length(seconds, short: true))
                .themeFont(printed ? .display : .body, size: printed ? 14 : 11, weight: lit ? .bold : .semibold)
                .monospacedDigit()
                .foregroundStyle(
                    lit && !marksUnder ? ThemeStyle.themeOnAccent : .themeInk.opacity(lit || !printed ? 1 : 0.64)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if lit { presetMark(shape) }
                }
                .themePlatter(printed ? 0 : 0.1, in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start a \(Self.spoken(seconds)) timer")
        .accessibilityAddTraits(lit ? .isSelected : [])
    }

    /// What marks the running preset: the accent behind it, glowing on a dark sheet, or the
    /// theme's line or dot under it.
    @ViewBuilder private func presetMark(_ shape: some Shape) -> some View {
        if marksUnder {
            SelectionMark(in: shape)
        } else {
            shape.fill(.themeAccent).shadow(color: glow(0.6), radius: 7)
        }
    }

    /// Whether the theme marks a choice with a line or a dot under it, rather than the accent behind.
    private var marksUnder: Bool {
        theme.controls?.selection == .underline || theme.controls?.selection == .dot
    }

    // MARK: Countdown

    /// Beside the dial: the countdown, when it started and rings, its controls, whether the Mac is
    /// kept awake, and the minutes field at the foot. A shorter notch drops the times, then the field.
    private var countdownColumn: some View {
        ViewThatFits(in: .vertical) {
            countdownDetails(times: true, field: true)
            countdownDetails(times: false, field: true)
            countdownDetails(times: false, field: false)
        }
    }

    private func countdownDetails(times: Bool, field: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(timer.countdown.map { "\(Self.length($0.total)) timer" } ?? "Timer")
                .themeFont(.display, size: 20, weight: .semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if times { countdownTimes.padding(.top, 3) }
            if let countdown = timer.countdown { countdownControls(countdown).padding(.top, 10) }
            if let until = timer.awakeUntil { awakeNote(until).padding(.top, 10) }
            Spacer(minLength: 8)
            if field { minutesField }
        }
    }

    /// When the countdown started and when it rings, or what's left while it's paused, or how to
    /// start one.
    private var countdownTimes: some View {
        Group {
            if let countdown = timer.countdown, let end = countdown.endsAt {
                ViewThatFits(in: .horizontal) {
                    Text("Started \(Self.clock(countdown.startedAt)) · rings at \(Self.clock(end))")
                    Text("Rings at \(Self.clock(end))")
                }
            } else if let countdown = timer.countdown {
                Text("Paused with \(formatTime(countdown.remaining)) left")
            } else {
                Text("Pick a length on the dial to start it.")
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .themeFont(.body, size: 11)
        .foregroundStyle(.themeInk.opacity(0.62))
        .lineLimit(1)
    }

    /// Beside the ring alone: the countdown and its controls, or the presets to start one; the
    /// minutes field when there's room.
    private var compactCountdownColumn: some View {
        ViewThatFits(in: .vertical) {
            compactCountdown(extras: true)
            compactCountdown(extras: false)
        }
    }

    private func compactCountdown(extras: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let countdown = timer.countdown {
                Group {
                    if let end = countdown.endsAt {
                        Text("\(Self.length(countdown.total)) · rings at \(Self.clock(end))")
                    } else {
                        Text("\(Self.length(countdown.total)) · paused")
                    }
                }
                .themeFont(.body, size: 11, weight: .semibold)
                .foregroundStyle(.themeInk.opacity(0.62))
                .lineLimit(1)
                countdownControls(countdown)
            } else {
                presetGrid
            }
            if extras {
                if let until = timer.awakeUntil { awakeNote(until) }
                Spacer(minLength: 0)
                minutesField
            }
        }
    }

    /// The presets in two rows of four, beside a ring with no room for them around it.
    private var presetGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(TimerFeature.presets, id: \.self) { seconds in
                gridChip(Text(Self.length(seconds))) { timer.start(seconds) }
                    .accessibilityLabel("Start a \(Self.spoken(seconds)) timer")
            }
        }
    }

    /// Pause or resume, a minute more, and cancel (⌘⌫); a narrow column words the last two shorter.
    private func countdownControls(_ countdown: Countdown) -> some View {
        ViewThatFits(in: .horizontal) {
            countdownControls(countdown, words: 2)
            countdownControls(countdown, words: 1)
            countdownControls(countdown, words: 0)
        }
    }

    /// `words` is how many of "+1 min" and "Cancel" keep their words; the rest shorten.
    private func countdownControls(_ countdown: Countdown, words: Int) -> some View {
        HStack(spacing: 6) {
            primary(
                countdown.isRunning ? "Pause" : "Resume", symbol: countdown.isRunning ? "pause.fill" : "play.fill"
            ) {
                countdown.isRunning ? timer.pause() : timer.resume()
            }
            chip(words > 0 ? "+1 min" : "+1m", help: "Add a minute", action: timer.addMinute)
            chip(words > 1 ? "Cancel" : nil, symbol: "xmark", help: "Cancel", action: timer.cancel)
                .keyboardShortcut(.delete, modifiers: .command)
        }
    }

    /// Any other length: minutes, then Return. While it has the keyboard, Space pauses or resumes and
    /// + adds a minute.
    private var minutesField: some View {
        HStack(spacing: 6) {
            ThemeSymbol("plus")
                .themeFont(.body, size: 10, weight: .semibold)
                .foregroundStyle(.themeInk.opacity(0.62))
            TextField(
                "Start a timer for this many minutes", text: $minutes,
                prompt: theme.prompt("Or type minutes", .caption)
            )
            .textFieldStyle(.plain)
            .themeFont(.body, size: 11.5)
            .onSubmit {
                guard let seconds = Self.seconds(fromMinutes: minutes) else { return }
                timer.start(seconds)
                minutes = ""
            }
            .onKeyPress(.space) {
                guard let countdown = timer.countdown else { return .ignored }
                countdown.isRunning ? timer.pause() : timer.resume()
                return .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "+")) { _ in
                guard timer.countdown != nil else { return .ignored }
                timer.addMinute()
                return .handled
            }
            Text("⏎")
                .themeFont(.body, size: 11)
                .foregroundStyle(.themeInk.opacity(0.62))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .themePlatter(0.06, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(
            "Minutes, then Return. While typing here, Space pauses, + adds a minute, ⌘⌫ cancels, ⌘1 to ⌘3 "
                + "switch modes, and ⌘Z brings back a timer you swapped.")
    }

    /// ⌘Z brings back the countdown a preset replaced, while the notch has the keyboard.
    @ViewBuilder private var undoSwapKey: some View {
        if timer.replaced != nil {
            Button("Undo", action: timer.undoSwap)
                .keyboardShortcut("z", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// While the Mac is kept awake, until when.
    private func awakeNote(_ until: Date) -> some View {
        HStack(spacing: 5) {
            ThemeSymbol("cup.and.saucer.fill")
                .themeFont(.body, size: 10)
                .foregroundStyle(.themeAccent)
            Text("Mac stays awake until \(until == .distantFuture ? "turned off" : Self.clock(until))")
        }
        .themeFont(.body, size: 11)
        .foregroundStyle(.themeInk.opacity(0.62))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    // MARK: Stopwatch

    /// The stopwatch's time where the dial is. Tenths need ten redraws a second, only while it runs
    /// on screen.
    private func stopwatchClock(large: Bool) -> some View {
        let watch = timer.stopwatch
        return TimelineView(.periodic(from: .now, by: watch.isRunning ? 0.1 : 3600)) { context in
            RollingTime(watch.elapsed(at: context.date), tenths: true)
                .themeFont(.numbers, size: large ? 40 : 30, weight: .semibold, design: .rounded)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Start or pause, then lap or reset, over every lap.
    private var stopwatchColumn: some View {
        let watch = timer.stopwatch
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                primary(watch.isRunning ? "Pause" : "Start", symbol: watch.isRunning ? "pause.fill" : "play.fill") {
                    timer.toggleStopwatch()
                }
                if watch.isRunning {
                    chip("Lap", help: "Lap") { timer.lap() }
                } else {
                    chip("Reset", help: "Reset", action: timer.resetStopwatch)
                        .disabled(watch.elapsed(at: .now) == 0)
                }
            }
            if !watch.laps.isEmpty { lapList(watch.laps) }
        }
    }

    /// Every lap, newest first, scrolling once they outgrow the notch. It sits outside the timeline,
    /// so it isn't rebuilt ten times a second.
    private func lapList(_ laps: [TimeInterval]) -> some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(laps.indices.reversed(), id: \.self) { index in
                    let split = laps[index] - (index > 0 ? laps[index - 1] : 0)
                    HStack {
                        Text("Lap \(index + 1)")
                        Spacer()
                        Text(formatTime(split, tenths: true)).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .themeFont(.body, .caption)
            .foregroundStyle(.themeInk.opacity(0.6))
            .padding(.vertical, 6)
        }
        .fadingEdges()
    }

    // MARK: Keep awake

    /// How long the Mac stays awake, where the dial is: the time left, or a cup while it's on until
    /// turned off, or off.
    private func awakeClock(large: Bool) -> some View {
        VStack(spacing: 6) {
            if let until = timer.awakeUntil, until != .distantFuture {
                // Redraws once a second, and only while it's on screen.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    RollingTime(until.timeIntervalSince(context.date), countsDown: true)
                        .themeFont(.numbers, size: large ? 40 : 30, weight: .semibold, design: .rounded)
                }
                Text("until \(Self.clock(until))")
                    .themeFont(.body, size: 11)
                    .foregroundStyle(.themeInk.opacity(0.62))
            } else {
                ThemeSymbol("cup.and.saucer.fill")
                    .themeFont(.body, size: large ? 30 : 22)
                    .foregroundStyle(timer.keepsAwake ? ThemeStyle.themeAccent : .themeInk.opacity(0.35))
                Text(timer.keepsAwake ? "Until you turn it off" : "Sleeps as usual")
                    .themeFont(.body, size: 11)
                    .foregroundStyle(.themeInk.opacity(0.62))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// While it's on: turn it off, or half an hour more; while it's off, how long to stay awake. A
    /// shorter notch drops the explanation.
    @ViewBuilder private var awakeColumn: some View {
        if let until = timer.awakeUntil {
            ViewThatFits(in: .vertical) {
                awakeControls(until, explained: true)
                awakeControls(until, explained: false)
            }
        } else {
            ViewThatFits(in: .vertical) {
                awakePresets(explained: true)
                awakePresets(explained: false)
            }
        }
    }

    private func awakeControls(_ until: Date, explained: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                primary("Turn Off", symbol: nil, action: timer.allowSleep)
                if until != .distantFuture {
                    chip("+30 min", help: "Half an hour more") { timer.extendAwake() }
                }
            }
            if explained {
                explanation(
                    until == .distantFuture
                        ? "Your Mac and its display stay awake until you turn it off."
                        : "Your Mac and its display stay awake until then.")
            }
        }
    }

    private func awakePresets(explained: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if explained {
                explanation("Keep your Mac and its display from sleeping through a download, a build, or a talk.")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(TimerFeature.awakePresets, id: \.self) { seconds in
                    gridChip(Text(Self.length(seconds))) { timer.keepAwake(for: seconds) }
                        .accessibilityLabel("Keep awake for \(Self.spoken(seconds))")
                }
                gridChip(ThemeSymbol("infinity")) { timer.keepAwake(for: nil) }
                    .help("Until you turn it off")
                    .accessibilityLabel("Keep awake until you turn it off")
            }
        }
    }

    private func explanation(_ text: String) -> some View {
        Text(text)
            .themeFont(.body, size: 11)
            .foregroundStyle(.themeInk.opacity(0.62))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Controls

    /// The main control: in the ink where the theme leaves controls plain (Black), else in the
    /// accent, with its text in what sits on that.
    private func primary(_ title: String, symbol: String?, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.controls?.radius ?? 14, style: .continuous)
        let inked = theme.controls == nil
        return Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { ThemeSymbol(symbol).themeFont(.body, size: 10, weight: .bold) }
                Text(title)
            }
            .fixedSize()  // never cut short: a narrow column picks shorter words instead
            .themeFont(.body, size: 12, weight: .semibold)
            .foregroundStyle(inked ? theme.surface.color.color : theme.color(.onAccent))
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(inked ? theme.color(.ink) : theme.color(.accent), in: shape)
            .themePlatter(0.14, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    /// A control on the theme's platter, in words, or as `symbol` alone when `title` is nil.
    private func chip(_ title: String?, symbol: String? = nil, help: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Group {
                if let title {
                    Text(title)
                } else if let symbol {
                    ThemeSymbol(symbol)
                }
            }
            .fixedSize()
            .themeFont(.body, size: 12, weight: .semibold)
            .padding(.horizontal, title == nil ? 9 : 10)
            .frame(height: 28)
            .themePlatter(0.1, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    /// A choice in a grid of them, as wide as its column.
    private func gridChip(_ label: some View, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .themeFont(.body, size: 11.5, weight: .semibold)
                .frame(maxWidth: .infinity, minHeight: 24)
                .themePlatter(0.1, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Words

    /// "25 min" or "1 hr"; `short`, "25m" or "1h".
    static func length(_ seconds: TimeInterval, short: Bool = false) -> String {
        Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: short ? .narrow : .abbreviated))
    }

    /// "17 minutes, 42 seconds", for VoiceOver.
    static func spoken(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded(.up)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    /// "4:32 PM", as the Mac writes times.
    static func clock(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    /// The seconds that typed minutes ask for ("25", "1.5", "1,5"), or nil for anything that isn't
    /// a length from a second to a day.
    static func seconds(fromMinutes text: String) -> TimeInterval? {
        let typed = text.trimmingCharacters(in: .whitespaces).replacing(",", with: ".")
        guard let minutes = Double(typed), minutes.isFinite else { return nil }
        let seconds = (minutes * 60).rounded()
        return (1...86_400).contains(seconds) ? seconds : nil
    }
}

/// The dial's size in the space the tab has. With room, the presets ring it as in the mock, scaled
/// to the height (up to 1.25 times) while the column beside it keeps its width; in a shorter notch
/// the ring fills the height alone.
private struct Dial {
    static let gap: CGFloat = 14
    /// A preset around the dial.
    static let chip = CGSize(width: 36, height: 20)
    /// What the column beside the dial needs for the switch and the controls.
    private static let column: CGFloat = 176
    /// Beside the ring alone, the column holds the presets too.
    private static let compactColumn: CGFloat = 200

    let ringed: Bool
    /// The mock's dial is 1.
    let scale: CGFloat
    let width: CGFloat
    let height: CGFloat
    /// Where the presets' centers sit.
    let presetRadius: CGFloat

    /// `reach` is how far the ring draws from its center at the mock's scale.
    init(fitting size: CGSize, reach: CGFloat) {
        // The presets sit 26 pt out from the ring, which clears the diagonal ones, plus half a chip.
        let outer = min((size.height - 74) / 2, (size.width - Self.column - Self.gap - 90) / 2, 1.25 * reach)
        ringed = outer >= 0.55 * reach
        if ringed {
            scale = outer / reach
            presetRadius = outer + 26
            width = 2 * outer + 90
            height = 2 * outer + 74
        } else {
            let side = max(0, min(size.height, size.width - Self.compactColumn - Self.gap))
            scale = max(0, side / 2 - 1) / reach
            presetRadius = 0
            width = side
            height = side
        }
    }

    /// The ring's centerline, 78 pt in the mock.
    var radius: CGFloat { 78 * scale }
}

/// How the dial draws its ring, from the theme's shapes: square controls cut it into blocks
/// (Terminal), a light sheet prints it thin with minute ticks (Paper), and the rest draw a thick arc
/// that glows on a dark sheet (Black).
private enum RingStyle {
    case arc, printed, blocks

    init(_ theme: Theme) {
        if theme.controls?.radius == 0 {
            self = .blocks
        } else {
            self = theme.appearance == .light ? .printed : .arc
        }
    }

    /// The ring's line at the mock's scale.
    var line: CGFloat {
        switch self {
        case .arc: 11
        case .printed: 3
        case .blocks: 12
        }
    }

    /// How far it draws from its center at the mock's scale: its 78 pt radius, and half its line or
    /// its ticks.
    var reach: CGFloat { self == .printed ? 78 + 13 : 78 + line / 2 }

    /// The time left's size at the mock's scale, for each style's face: SF Rounded, Newsreader, and
    /// IBM Plex Mono draw the same digits this wide.
    var digits: CGFloat {
        switch self {
        case .arc: 44
        case .printed: 50
        case .blocks: 36
        }
    }
}

/// The ring cut into forty square-ended blocks, `lit` (0...1) of them from the top going clockwise.
/// It animates by lighting them in turn.
private struct BlockRing: Shape {
    var lit: Double

    var animatableData: Double {
        get { lit }
        set { lit = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        // A block every 9°, 6.5° long, lit once all of it is inside.
        let count = lit * 360 < 6.5 ? 0 : min(40, Int((lit * 360 - 6.5) / 9) + 1)
        return Path { path in
            for block in 0..<count {
                let start = Angle.degrees(Double(block) * 9 - 90)
                let end = start + .degrees(6.5)
                path.move(
                    to: CGPoint(x: center.x + radius * cos(start.radians), y: center.y + radius * sin(start.radians)))
                path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
            }
        }
    }
}

/// A printed dial's minute marks: sixty around the ring, every fifth longer.
private struct Ticks: Shape {
    let inner: CGFloat
    let minor: CGFloat
    let major: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            for minute in 0..<60 {
                let angle = Double(minute) * .pi / 30
                let (x, y) = (sin(angle), -cos(angle))
                let outer = minute % 5 == 0 ? major : minor
                path.move(to: CGPoint(x: rect.midX + inner * x, y: rect.midY + inner * y))
                path.addLine(to: CGPoint(x: rect.midX + outer * x, y: rect.midY + outer * y))
            }
        }
    }
}
