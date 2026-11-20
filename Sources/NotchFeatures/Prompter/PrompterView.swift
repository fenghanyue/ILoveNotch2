// SPDX-License-Identifier: MIT
import AppKit
import NotchTheme
import SwiftUI

/// The prompter tab: the script to edit, or to read in big type under the camera, with one strip
/// of controls under it.
struct PrompterView: View {
    @Bindable var prompter: PrompterFeature

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            if prompter.isReading { reading } else { editor }
            if let problem = prompter.problem { problemRow(problem) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Editing

    private var editor: some View {
        VStack(spacing: 8) {
            TextEditor(text: $prompter.script)
                .themeFont(.body, .callout)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Script")
                .padding(6)
                .themePlatter(0.06, in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if prompter.script.isEmpty {
                        Text("Paste or type your script, or import a text file, Markdown, or a deck's speaker notes.")
                            .themeFont(.body, .callout)
                            .foregroundStyle(.themeInk.opacity(0.4))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            HStack(spacing: 4) {
                ForEach(PrompterFeature.Mode.allCases, id: \.self, content: modeButton)
                Spacer(minLength: 4)
                control("Import\u{2026}", prompter.importScript)
                control("Start", prompter.start)
                    .disabled(prompter.script.allSatisfy(\.isWhitespace))
            }
        }
    }

    private func modeButton(_ mode: PrompterFeature.Mode) -> some View {
        Button(mode.title) { prompter.mode = mode }
            .buttonStyle(.plain)
            .themeFont(.body, .caption, weight: .semibold)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .themeSelectionInk(prompter.mode == mode, unlit: 1)
            .background {
                if prompter.mode == mode { SelectionMark() }
            }
            .help(Self.explanation(mode))
            .accessibilityHint(Self.explanation(mode))
            .accessibilityAddTraits(prompter.mode == mode ? .isSelected : [])
    }

    private static func explanation(_ mode: PrompterFeature.Mode) -> String {
        switch mode {
        case .voice: "Follows the words you say and waits when you pause. Recognized on this Mac."
        case .scroll: "Moves on at a steady pace. No microphone."
        case .words: "Moves on at a steady pace while it hears you speak."
        }
    }

    private func control(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .themeFont(.body, .callout, weight: .semibold)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .themePlatter(0.14, in: Capsule())
    }

    // MARK: Reading

    /// Room on each side of the script's column, for the reading line's cue.
    private static let margin: CGFloat = 26
    private static let widestColumn: CGFloat = 560
    /// How far the reading line's band reaches past the column on each side.
    private static let bandOutset: CGFloat = 8

    private var reading: some View {
        VStack(spacing: 6) {
            script
            // Narrower notches show the modes as icons, then tuck size, mirror, import, and edit into
            // a menu, so the strip never clips.
            ViewThatFits(in: .horizontal) {
                strip(labels: true, compact: false)
                strip(labels: false, compact: false)
                strip(labels: false, compact: true)
            }
        }
    }

    /// The script in a column under the camera, the line to read on a marked reading line and the
    /// lines read above it. Mirrored for a teleprompter's glass, all of it flips.
    private var script: some View {
        let style = scriptStyle
        return GeometryReader { proxy in
            let column = max(min(proxy.size.width - 2 * Self.margin, Self.widestColumn), 0)
            ZStack(alignment: .top) {
                readingLine(style, column: column)
                    .offset(y: style.readingTop(in: proxy.size.height) - style.lineSpacing / 2)
                ScriptText(
                    script: prompter.script, ranges: prompter.wordRanges, current: prompter.current, style: style,
                    glide: glide, pick: pick
                )
                .frame(width: column)
                .mask {
                    let sliver = style.sliver(in: proxy.size.height)
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: style.lineSpacing)
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: sliver > 0 ? style.lineSpacing : style.fade)
                        Color.clear.frame(height: sliver)
                    }
                }
                .accessibilityLabel("Script")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .clipped()
        .scaleEffect(x: prompter.mirrored ? -1 : 1, y: 1)
    }

    /// The script in the theme's display face. Read words take the tertiary ink; the next word sits
    /// on the theme's highlight in its onHighlight ink: a soft glowing pill where the theme has no
    /// highlight of its own (Black), a block in a square theme (Terminal), a highlighter's stroke
    /// in the others (Paper).
    private var scriptStyle: ScriptStyle {
        let ink = NSColor(theme.color(.ink))
        let mark: ScriptStyle.Mark =
            theme.colors.highlight == nil ? .glow : theme.controls?.radius == 0 ? .block : .highlighter
        return ScriptStyle(
            font: theme.nsFont(.display, size: prompter.textSize, weight: .medium), ink: ink,
            read: NSColor(theme.color(.tertiary)), current: theme.colors.onHighlight.map { NSColor($0.color) } ?? ink,
            highlight: NSColor(theme.color(.highlight)), mark: mark)
    }

    /// Seconds a word while Scroll moves the script on, which it glides by; nil while it stands
    /// still or lifts a line at a time.
    private var glide: TimeInterval? {
        guard prompter.isRunning, prompter.mode == .scroll else { return nil }
        return 1 / (PrompterFeature.wordsPerSecond * prompter.speed)
    }

    /// Carries on from the word at a character clicked, or scrolled to the reading line.
    private func pick(_ offset: Int) {
        let ranges = prompter.wordRanges
        prompter.jump(to: ranges.firstIndex { NSMaxRange($0) > offset } ?? max(ranges.count - 1, 0))
    }

    /// The reading line's marker: a band a little wider than the column with a cue at its start, and
    /// behind it, where the next word glows, a faint glow of the highlight.
    private func readingLine(_ style: ScriptStyle, column: CGFloat) -> some View {
        let glows = style.mark == .glow
        return Color.clear
            .frame(width: column + 2 * Self.bandOutset, height: style.lineHeight + style.lineSpacing)
            .themePlatter(0.08, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background {
                if glows {
                    EllipticalGradient(colors: [theme.color(.highlight).opacity(0.14), .clear])
                        .frame(width: column * 0.9, height: style.lineHeight * 3.4)
                }
            }
            .overlay(alignment: .leading) {
                ThemeSymbol("arrowtriangle.right.fill")
                    .themeFont(.body, size: 8)
                    .foregroundStyle(glows ? .themeHighlight : .themeInk)
                    .offset(x: -11)
            }
            .accessibilityHidden(true)
    }

    /// Every control in one strip: how the script moves and how fast, its size, the mirror, a new
    /// script, the editor, whether screen sharing sees it, the time left, and play or pause.
    private func strip(labels: Bool, compact: Bool) -> some View {
        HStack(spacing: 4) {
            modeSwitch(labels: labels)
            if prompter.mode != .voice { speedControl }  // Voice goes at your pace
            if !compact {
                HStack(spacing: 0) {
                    sizeButton(larger: false)
                    sizeButton(larger: true)
                }
                icon("flip.horizontal", "Mirror for a teleprompter's glass", lit: prompter.mirrored) {
                    prompter.mirrored.toggle()
                }
                icon("tray.and.arrow.down", "Import a script", action: prompter.importScript)
                icon("pencil", "Edit the script", action: prompter.edit)
            }
            sharing
            Spacer(minLength: 2)
            timeLeft
            if compact { more }
            playButton
        }
        .themeFont(.body, .caption, weight: .semibold)
        .buttonStyle(.plain)
        .padding(.horizontal, 3)
        .frame(height: 30)
        .themePlatter(0.08, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Voice, Scroll, and Words, by name or, where the strip is narrow, by icon.
    private func modeSwitch(labels: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(PrompterFeature.Mode.allCases, id: \.self) { mode in
                let on = prompter.mode == mode
                Button {
                    prompter.mode = mode
                } label: {
                    Group {
                        if labels { Text(mode.title) } else { ThemeSymbol(mode.symbol) }
                    }
                    .padding(.horizontal, labels ? 6 : 4)
                    .frame(minWidth: 22, minHeight: 20)
                    .themeSelectionInk(on, unlit: 0.6)
                    .background {
                        if on { SelectionMark(in: RoundedRectangle(cornerRadius: 7), strength: 0.18) }
                    }
                    .contentShape(Rectangle())
                }
                .help("\(mode.title): \(Self.explanation(mode))")
                .accessibilityLabel(mode.title)
                .accessibilityHint(Self.explanation(mode))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .themePlatter(0.07, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// Slower and faster, a step at a time; the arrow keys do the same.
    private var speedControl: some View {
        HStack(spacing: 0) {
            icon("minus", "Slower") { changeSpeed(by: -1) }
                .disabled(prompter.speed <= PrompterFeature.speeds.lowerBound)
                .keyboardShortcut(.leftArrow, modifiers: [])
            Text("\(prompter.speed.formatted())×")
                .monospacedDigit()
                .frame(minWidth: 30)
                .accessibilityLabel("Speed, \(prompter.speed.formatted()) times")
            icon("plus", "Faster") { changeSpeed(by: 1) }
                .disabled(prompter.speed >= PrompterFeature.speeds.upperBound)
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
    }

    private func changeSpeed(by steps: Double) {
        let (speeds, speed) = (PrompterFeature.speeds, prompter.speed + steps * PrompterFeature.speedStep)
        prompter.speed = min(max(speed, speeds.lowerBound), speeds.upperBound)
    }

    /// A small A and a large one, in the theme's face; Command-minus and Command-plus do the same.
    private func sizeButton(larger: Bool) -> some View {
        Button {
            prompter.textSize += larger ? 2 : -2
        } label: {
            Text("A")
                .themeFont(.body, size: larger ? 13 : 9, weight: .semibold)
                .foregroundStyle(.themeSecondary)
                .frame(width: larger ? 19 : 15, height: 22)
                .contentShape(Rectangle())
        }
        .disabled(
            larger
                ? prompter.textSize >= PrompterFeature.textSizes.upperBound
                : prompter.textSize <= PrompterFeature.textSizes.lowerBound
        )
        .keyboardShortcut(larger ? "=" : "-", modifiers: .command)
        .help(larger ? "Larger text (Command-plus)" : "Smaller text (Command-minus)")
        .accessibilityLabel(larger ? "Larger text" : "Smaller text")
    }

    /// Whether calls and recordings see the notch while the script is up; Settings sets it.
    private var sharing: some View {
        let hidden = prompter.hidesFromScreenSharing
        let label = hidden ? "Hidden from screen sharing" : "Showing in screen sharing"
        return ThemeSymbol(hidden ? "eye.slash" : "eye")
            .foregroundStyle(.themeSecondary)
            .frame(width: 18, height: 22)
            .help("\(label). Change it in Settings › Prompter.")
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isImage)
    }

    /// The time left; it ticks once a second, and only while the script moves.
    private var timeLeft: some View {
        TimelineView(.periodic(from: .now, by: prompter.isRunning ? 1 : 3600)) { context in
            let elapsed = formatTime(prompter.stopwatch.elapsed(at: context.date), roundingUp: false)
            let left = formatTime(prompter.remaining(at: context.date))
            Text("\(left) left")
                .monospacedDigit()
                .foregroundStyle(.themeSecondary)
                .lineLimit(1)
                .fixedSize()
                .help("\(elapsed) read")
                .accessibilityLabel("\(elapsed) read, about \(left) left")
        }
    }

    /// Size, the mirror, import, and edit, where the strip has no room for them.
    private var more: some View {
        Menu {
            Button("Larger Text") { prompter.textSize += 2 }
                .disabled(prompter.textSize >= PrompterFeature.textSizes.upperBound)
            Button("Smaller Text") { prompter.textSize -= 2 }
                .disabled(prompter.textSize <= PrompterFeature.textSizes.lowerBound)
            Toggle("Mirror", isOn: $prompter.mirrored)
            Divider()
            Button("Import a Script\u{2026}", action: prompter.importScript)
            Button("Edit the Script", action: prompter.edit)
        } label: {
            ThemeSymbol("ellipsis.circle").foregroundStyle(.themeSecondary).frame(width: 22, height: 22)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Text size, mirror, import, and edit")
        .accessibilityLabel("More")
    }

    /// Read or pause; once the script's read, back to its start to read it again.
    private var playButton: some View {
        let finished = prompter.isFinished
        let (symbol, label) =
            finished
            ? ("arrow.clockwise", "Read again") : prompter.isRunning ? ("pause.fill", "Pause") : ("play.fill", "Read")
        return Button {
            if finished { prompter.restart() }
            prompter.toggle()
        } label: {
            ThemeSymbol(symbol)
                .themeFont(.body, size: 10, weight: .bold)
                .foregroundStyle(onPlay)
                .frame(width: 24, height: 24)
                .background { playBacking }
                .contentShape(Rectangle())
        }
        .keyboardShortcut(.space, modifiers: [])
        .help("\(label) (Space, or Control-Option-P from any app)")
        .accessibilityLabel(label)
    }

    /// Play's backing: the accent where the theme selects on it, a ring of ink in an outlined
    /// theme, else a disc of ink.
    @ViewBuilder private var playBacking: some View {
        if theme.selectsOnAccent {
            if theme.controls?.radius == 0 { Rectangle().fill(.themeAccent) } else { Circle().fill(.themeAccent) }
        } else if theme.controls?.style == .outline {
            Circle().strokeBorder(.themeInk, lineWidth: 1.5)
        } else {
            Circle().fill(.themeInk)
        }
    }

    /// The glyph on play's backing: the accent's ink, the ink on a ring, the notch's own color on ink.
    private var onPlay: Color {
        if theme.selectsOnAccent { return theme.color(.onAccent) }
        return theme.controls?.style == .outline ? theme.color(.ink) : theme.surface.color.color
    }

    private func icon(_ symbol: String, _ label: String, lit: Bool = false, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            ThemeSymbol(symbol)
                .foregroundStyle(lit ? .themeInk : .themeSecondary)
                .frame(width: 20, height: 22)
                .themePlatter(lit ? 0.16 : 0, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(lit ? .isSelected : [])
    }

    // MARK: Problems

    @ViewBuilder private func problemRow(_ problem: PrompterFeature.Problem) -> some View {
        switch problem {
        case .microphone:
            banner(
                "Microphone access is off. Allow ILoveNotch in Privacy & Security, or use Scroll.",
                fix: ("Open Settings", { NSWorkspace.shared.open(.privacySettings("Privacy_Microphone")) }))
        case .speechRecognition:
            banner(
                "Speech Recognition is off. Allow ILoveNotch in Privacy & Security, or use Scroll or Words.",
                fix: ("Open Settings", { NSWorkspace.shared.open(.privacySettings("Privacy_SpeechRecognition")) }))
        case .message(let message):
            banner(message, fix: nil)
        }
    }

    private func banner(_ message: String, fix: (label: String, perform: () -> Void)?) -> some View {
        HStack(spacing: 8) {
            ThemeSymbol("exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(message).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            if let fix { control(fix.label, fix.perform).themeFont(.body, .caption, weight: .semibold) }
        }
        .themeFont(.body, .caption)
        .accessibilityElement(children: .combine)
    }
}

/// How the script is drawn: its face, its inks for the words to come and the words read, and how
/// the next word is marked.
private struct ScriptStyle: Equatable {
    var font: NSFont
    var ink: NSColor
    var read: NSColor
    /// The next word's ink, on its mark.
    var current: NSColor
    var highlight: NSColor
    var mark: Mark

    /// What lights the next word in the highlight: a soft glowing pill, a square block, or a
    /// highlighter's stroke with soft ends.
    enum Mark {
        case glow, block, highlighter
    }

    var lineSpacing: CGFloat { font.pointSize * 0.25 }

    /// A line's height, without the spacing under it.
    @MainActor var lineHeight: CGFloat { Self.metrics.defaultLineHeight(for: font) }
    @MainActor private static let metrics = NSLayoutManager()

    /// How far a line the bottom edge cuts through fades out: half a line.
    @MainActor var fade: CGFloat { (lineHeight / 2).rounded() }

    /// What shows of the line the bottom edge cuts through in a script `height` tall, when it's too
    /// little to read and so left out; 0 when it's half a line or more, and fades out instead.
    @MainActor func sliver(in height: CGFloat) -> CGFloat {
        let shown = (height - readingTop(in: height)).truncatingRemainder(dividingBy: lineHeight + lineSpacing)
        return shown < lineHeight / 2 ? shown : 0
    }

    /// The reading line's top in a script `height` tall: about two-fifths of the way down the room
    /// the other lines share, under whole read lines, the first a line's spacing from the top, so
    /// the one above it is out of sight rather than cut.
    @MainActor func readingTop(in height: CGFloat) -> CGFloat {
        let pitch = lineHeight + lineSpacing
        return lineSpacing + max(0, (((height - lineHeight) * 0.4 - lineSpacing) / pitch).rounded(.down)) * pitch
    }
}

/// The script as it's read: the words read so far dimmed, the next one lit, and the lines to come
/// under it. AppKit lays the text out once; moving on recolors two ranges and scrolls.
private struct ScriptText: NSViewRepresentable {
    let script: String
    let ranges: [NSRange]
    let current: Int
    let style: ScriptStyle
    let glide: TimeInterval?
    let pick: (Int) -> Void

    func makeNSView(context: Context) -> ScriptScrollView { ScriptScrollView() }

    func updateNSView(_ view: ScriptScrollView, context: Context) {
        view.onPick = pick
        view.show(script, style: style)
        view.follow(current < ranges.count ? ranges[current] : nil, glide: glide)
    }
}

private final class ScriptScrollView: NSScrollView {
    private let text = NSTextView(usingTextLayoutManager: false)  // TextKit 1, for its temporary colors
    private let layout = MarkingLayout()
    private var script = ""
    private var style: ScriptStyle?
    /// The next word to read; nil once the script is done.
    private var current: NSRange?
    /// Seconds a word while the script glides on (Scroll); nil while it lifts a line at a time.
    private var glide: TimeInterval?
    /// The text was replaced, so its words need coloring again.
    private var uncolored = true
    /// Carries on from a character: one clicked, or on the line scrolled to the reading line.
    var onPick: ((Int) -> Void)?
    /// Waits for scrolling by hand to stop, to see where it left the script.
    private var nudge: Task<Void, Never>?

    init() {
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = false
        automaticallyAdjustsContentInsets = false
        // The document first: a text view that sizes itself before it's in the (flipped) clip view
        // grows upward, and its first line would sit above the top for good.
        documentView = text
        text.textContainer?.replaceLayoutManager(layout)
        text.isEditable = false
        text.isSelectable = false
        text.drawsBackground = false
        text.wantsLayer = true  // for the lit word's fade
        text.textContainer?.lineFragmentPadding = 0
        text.textContainer?.widthTracksTextView = true
        text.isVerticallyResizable = true
        text.autoresizingMask = .width
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        text.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked)))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ script: String, style: ScriptStyle) {
        guard script != self.script || style != self.style else { return }
        (self.script, self.style) = (script, style)
        layout.style = style
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = style.lineSpacing
        text.textStorage?.setAttributedString(
            NSAttributedString(
                string: script,
                attributes: [.font: style.font, .foregroundColor: style.ink, .paragraphStyle: paragraph]))
        makeRoom()
        uncolored = true
    }

    func follow(_ next: NSRange?, glide: TimeInterval?) {
        let moved = next != current || uncolored
        guard moved || glide != self.glide, let style else { return }
        self.glide = glide
        if moved {
            (current, uncolored) = (next, false)
            recolor(style)
        }
        scrollToCurrent(animated: true)
    }

    /// The words read in the read ink, and the next one on its mark, faded in.
    private func recolor(_ style: ScriptStyle) {
        if !Self.reducesMotion {
            let fade = CATransition()  // a crossfade
            fade.duration = 0.1
            text.layer?.add(fade, forKey: "fade")
        }
        let all = NSRange(location: 0, length: (script as NSString).length)
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: all)
        layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
        let read = NSRange(location: 0, length: current?.location ?? all.length)
        layout.addTemporaryAttribute(.foregroundColor, value: style.read, forCharacterRange: read)
        if let current {
            layout.addTemporaryAttribute(.foregroundColor, value: style.current, forCharacterRange: current)
            layout.addTemporaryAttribute(.backgroundColor, value: style.highlight, forCharacterRange: current)
        }
        text.setNeedsDisplay(text.visibleRect)  // a glow reaches past its word
    }

    /// A new size rewraps the lines and moves the reading line.
    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        makeRoom()
        scrollToCurrent(animated: false)
    }

    /// Room above the first line and under the last, so either can sit on the reading line.
    private func makeRoom() {
        guard let style else { return }
        let top = style.readingTop(in: bounds.height)
        let room = max(top, bounds.height - top - style.lineHeight).rounded()
        guard text.textContainerInset.height != room else { return }
        text.textContainerInset = NSSize(width: 0, height: room)
        text.sizeToFit()
    }

    /// Keeps the next word's line on the reading line: lifted there as the line before is finished,
    /// or while Scroll glides, rising through it word by word at the script's pace. Done, the last
    /// line stays there.
    private func scrollToCurrent(animated: Bool) {
        guard nudge == nil, let style, let container = text.textContainer else { return }
        layout.ensureLayout(for: container)
        let glyphs = layout.numberOfGlyphs
        guard glyphs > 0 else { return }
        let glyph = min(current.map { layout.glyphIndexForCharacter(at: $0.location) } ?? glyphs, glyphs - 1)
        var line = NSRange()
        let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &line)
        let motion = animated && !Self.reducesMotion
        let glide = motion && current != nil ? self.glide : nil
        let risen = glide == nil ? 0 : rect.height * CGFloat(glyph - line.location) / CGFloat(max(line.length, 1))
        let top = rect.minY + text.textContainerOrigin.y + risen - style.readingTop(in: bounds.height)
        guard abs(top - contentView.bounds.origin.y) > 0.5 else { return }
        if motion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = glide ?? 0.3
                context.timingFunction = CAMediaTimingFunction(name: glide == nil ? .easeOut : .linear)
                context.allowsImplicitAnimation = true
                contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: top))
            }
        } else {
            contentView.setBoundsOrigin(NSPoint(x: 0, y: top))
        }
        reflectScrolledClipView(contentView)
    }

    private static var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    @objc private func clicked(_ click: NSClickGestureRecognizer) {
        if let offset = character(at: click.location(in: text)) { onPick?(offset) }
    }

    /// Scrolling by hand moves the reading line: once it stops, the script carries on from the
    /// line left there, or settles back when that's the line being read.
    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        nudge?.cancel()
        nudge = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            nudge = nil
            guard let style,
                let offset = character(
                    at: NSPoint(x: 0, y: contentView.bounds.minY + style.readingTop(in: bounds.height) + 1))
            else { return }
            var line = NSRange()
            layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: offset), effectiveRange: &line)
            if let current, NSLocationInRange(layout.glyphIndexForCharacter(at: current.location), line) {
                scrollToCurrent(animated: true)
            } else {
                onPick?(offset)
            }
        }
    }

    /// The script's character at `point` in the text view, or the nearest one.
    private func character(at point: NSPoint) -> Int? {
        guard let container = text.textContainer, layout.numberOfGlyphs > 0 else { return nil }
        let origin = text.textContainerOrigin
        let glyph = layout.glyphIndex(for: NSPoint(x: point.x - origin.x, y: point.y - origin.y), in: container)
        return layout.characterIndexForGlyph(at: glyph)
    }
}

/// Draws the next word's temporary background as the style's mark, a little wider than the word
/// and the height of its line's letters.
private final class MarkingLayout: NSLayoutManager {
    var style: ScriptStyle?

    override func fillBackgroundRectArray(
        _ rectArray: UnsafePointer<NSRect>, count rectCount: Int, forCharacterRange charRange: NSRange, color: NSColor
    ) {
        guard let style else {
            super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
            return
        }
        let em = style.font.pointSize
        let height = defaultLineHeight(for: style.font)
        let pad: CGFloat =
            switch style.mark {
            case .glow: 0.12
            case .block: 0.1
            case .highlighter: 0.16
            }
        for rect in UnsafeBufferPointer(start: rectArray, count: rectCount) {
            var box = rect.insetBy(dx: -em * pad, dy: 0)
            box.size.height = min(box.height, height)
            NSGraphicsContext.saveGraphicsState()
            switch style.mark {
            case .block:
                color.setFill()
                box.fill()
            case .glow:
                let glow = NSShadow()
                glow.shadowBlurRadius = em * 0.9
                glow.shadowColor = color.withAlphaComponent(0.45)
                glow.set()
                color.withAlphaComponent(0.3).setFill()
                NSBezierPath(roundedRect: box, xRadius: em * 0.36, yRadius: em * 0.36).fill()
            case .highlighter:
                NSBezierPath(roundedRect: box, xRadius: em * 0.12, yRadius: em * 0.12).addClip()
                NSGradient(
                    colorsAndLocations: (color.withAlphaComponent(0), 0), (color, 0.06),
                    (color.withAlphaComponent(0.85), 0.94), (color.withAlphaComponent(0), 1)
                )?
                .draw(in: box, angle: 0)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
